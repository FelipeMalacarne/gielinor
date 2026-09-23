#!/usr/bin/env python3
"""Reconcile Bazarr's language profile and defaults from a ConfigMap."""

from __future__ import annotations

import json
import os
import time
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


BAZARR_URL = os.environ.get("BAZARR_URL", "http://127.0.0.1:6767")
CONFIG_PATH = Path("/config/config/config.yaml")
DESIRED_PATH = Path("/profile-sync/bazarr-profile.json")
POLL_SECONDS = int(os.environ.get("POLL_SECONDS", "300"))
RETRY_SECONDS = int(os.environ.get("RETRY_SECONDS", "30"))


def read_api_key() -> str:
    in_auth = False
    for raw_line in CONFIG_PATH.read_text().splitlines():
        line = raw_line.rstrip()
        if line == "auth:":
            in_auth = True
            continue
        if in_auth and line and not line.startswith("  "):
            break
        if in_auth and line.strip().startswith("apikey:"):
            value = line.split(":", 1)[1].strip()
            return value.strip("'\"")
    raise RuntimeError("Bazarr API key was not found in config.yaml")


def api_request(path: str, method: str = "GET", form: list[tuple[str, str]] | None = None):
    body = None
    headers = {"X-API-KEY": read_api_key()}
    if form is not None:
        body = urlencode(form).encode()
        headers["Content-Type"] = "application/x-www-form-urlencoded"
    request = Request(f"{BAZARR_URL}{path}", data=body, headers=headers, method=method)
    with urlopen(request, timeout=30) as response:
        payload = response.read()
        if not payload:
            return response.status, None
        return response.status, json.loads(payload)


def profile_key(profile: dict) -> int:
    return int(profile["profileId"])


def reconcile() -> None:
    desired = json.loads(DESIRED_PATH.read_text())
    desired_id = profile_key(desired)
    desired_languages = set(desired.get("enabledLanguages", []))

    _, settings_response = api_request("/api/system/settings")
    _, profiles_response = api_request("/api/system/languages/profiles")
    _, languages_response = api_request("/api/system/languages")

    settings = settings_response or {}
    profiles = list(profiles_response or [])
    languages = list(languages_response or [])
    existing = {profile_key(profile): profile for profile in profiles}
    profile_changed = existing.get(desired_id) != {
        key: value for key, value in desired.items() if key != "enabledLanguages"
    }
    if profile_changed:
        existing[desired_id] = {
            key: value for key, value in desired.items() if key != "enabledLanguages"
        }

    enabled_languages = {
        language["code2"] for language in languages if language.get("enabled")
    }
    wanted_languages = sorted(enabled_languages | desired_languages)
    language_changed = wanted_languages != sorted(enabled_languages)

    general = settings.get("general", {})
    defaults_changed = (
        general.get("movie_default_enabled") is not True
        or str(general.get("movie_default_profile")) != str(desired_id)
        or general.get("serie_default_enabled") is not True
        or str(general.get("serie_default_profile")) != str(desired_id)
    )

    if profile_changed or language_changed or defaults_changed:
        form = [
            ("settings-general-movie_default_enabled", "true"),
            ("settings-general-movie_default_profile", str(desired_id)),
            ("settings-general-serie_default_enabled", "true"),
            ("settings-general-serie_default_profile", str(desired_id)),
            ("languages-profiles", json.dumps(list(existing.values()))),
        ]
        form.extend(("languages-enabled", code) for code in wanted_languages)
        api_request("/api/system/settings", method="POST", form=form)
        print("profile-sync: applied ptbr profile/defaults", flush=True)

    assign_unprofiled("/api/movies?profileid=none&length=-1", "radarrid", "radarrId", desired_id)
    assign_unprofiled("/api/series?profileid=none&length=-1", "seriesid", "sonarrSeriesId", desired_id)


def assign_unprofiled(path: str, id_field: str, response_field: str, profile_id: int) -> None:
    _, response = api_request(path)
    for item in (response or {}).get("data", []):
        media_id = item.get(response_field)
        if media_id is None:
            continue
        api_request(
            "/api/movies" if id_field == "radarrid" else "/api/series",
            method="POST",
            form=[(id_field, str(media_id)), ("profileid", str(profile_id))],
        )
        api_request(
            "/api/movies" if id_field == "radarrid" else "/api/series",
            method="PATCH",
            form=[(id_field, str(media_id)), ("action", "search-missing")],
        )
        print(f"profile-sync: assigned profile {profile_id} to {id_field}={media_id}", flush=True)


def main() -> None:
    while True:
        try:
            reconcile()
        except (HTTPError, URLError, OSError, RuntimeError, ValueError, KeyError) as error:
            status = getattr(error, "code", "error")
            print(f"profile-sync: waiting/retry ({type(error).__name__}: {status})", flush=True)
            time.sleep(RETRY_SECONDS)
            continue
        time.sleep(POLL_SECONDS)


if __name__ == "__main__":
    main()

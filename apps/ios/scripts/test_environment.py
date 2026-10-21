#!/usr/bin/env python3
"""Check real build configurations and fail-closed packaging without Xcode."""
import copy
import plistlib
import unittest
from pathlib import Path
from configure_environment import validate

ROOT = Path(__file__).resolve().parents[1]


def configuration(name):
    settings = {}
    for line in (ROOT / 'Configuration' / (name + '.xcconfig')).read_text().splitlines():
        if '=' in line and not line.startswith('//'):
            key, value = line.split('=', 1)
            settings[key.strip()] = value.strip().replace('$()', '')
    info = plistlib.loads((ROOT / 'Multiverse/Resources/Info.plist').read_bytes())
    info['CFBundleIdentifier'] = settings['MULTIVERSE_BUNDLE_ID']
    info['MultiverseEnvironment'] = settings['MULTIVERSE_ENVIRONMENT']
    info['MultiverseAPIBaseURL'] = settings['MULTIVERSE_API_BASE_URL']
    info['CFBundleURLTypes'] = [{'CFBundleURLSchemes': [settings['MULTIVERSE_URL_SCHEME'], settings['MULTIVERSE_GOOGLE_REVERSED_CLIENT_ID']]}]
    firebase = plistlib.loads((ROOT / settings['MULTIVERSE_FIREBASE_PLIST']).read_bytes())
    return info, firebase


class EnvironmentPackagingTests(unittest.TestCase):
    def test_real_configurations_are_consistent_and_distinct(self):
        staging, staging_firebase = configuration('Staging')
        production, production_firebase = configuration('Production')
        validate(staging, staging_firebase)
        validate(production, production_firebase)
        for key in ('BUNDLE_ID', 'PROJECT_ID', 'GOOGLE_APP_ID', 'CLIENT_ID', 'REVERSED_CLIENT_ID'):
            self.assertNotEqual(staging_firebase[key], production_firebase[key])
        self.assertNotEqual(staging['CFBundleIdentifier'], production['CFBundleIdentifier'])

    def test_wrong_firebase_or_api_cannot_be_packaged(self):
        staging, firebase = configuration('Staging')
        production, production_firebase = configuration('Production')
        with self.assertRaises(ValueError):
            validate(staging, production_firebase)
        for value in (production['MultiverseAPIBaseURL'], 'http://public.example/api/v1', 'https://host/api/v1?token=x'):
            info = copy.deepcopy(staging)
            info['MultiverseAPIBaseURL'] = value
            with self.assertRaises(ValueError):
                validate(info, firebase)
        for value in ('', 'http://localhost:3000/api/v1', 'https://staging.example/api/v1'):
            info = copy.deepcopy(production)
            info['MultiverseAPIBaseURL'] = value
            with self.assertRaises(ValueError):
                validate(info, production_firebase)

    def test_other_environment_callback_is_rejected(self):
        info, firebase = configuration('Staging')
        info['CFBundleURLTypes'].append({'CFBundleURLSchemes': ['multiverse']})
        with self.assertRaises(ValueError):
            validate(info, firebase)


if __name__ == '__main__':
    unittest.main()

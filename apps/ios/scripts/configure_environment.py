#!/usr/bin/env python3
"""Validate the built app's deployment identity before bundling its Firebase config."""
import os
import plistlib
import shutil
from pathlib import Path
from urllib.parse import urlsplit


def validate(info, firebase):
    environment = info.get('MultiverseEnvironment')
    identities = {
        'staging': ('com.nexussoft.multiverse.staging', 'multiverse-staging-7f87c', 'multiverse-staging'),
        'production': ('com.nexussoft.multiverse', 'multiverse-7f87c', 'multiverse'),
    }
    if environment not in identities:
        raise ValueError('Unknown deployment environment')
    bundle, project, scheme = identities[environment]
    if info.get('CFBundleIdentifier') != bundle or firebase.get('BUNDLE_ID') != bundle or firebase.get('PROJECT_ID') != project:
        raise ValueError('Firebase, app bundle and deployment environment must match')
    schemes = [s for entry in info.get('CFBundleURLTypes', []) for s in entry.get('CFBundleURLSchemes', [])]
    if scheme not in schemes or not firebase.get('REVERSED_CLIENT_ID') or firebase['REVERSED_CLIENT_ID'] not in schemes:
        raise ValueError('OAuth and app URL schemes must match the selected Firebase project')
    other_scheme = 'multiverse' if environment == 'staging' else 'multiverse-staging'
    if other_scheme in schemes:
        raise ValueError('App cannot register the other environment URL scheme')
    value = info.get('MultiverseAPIBaseURL', '')
    if not value and environment == 'staging':
        return  # Explicitly unavailable until staging infrastructure is provisioned.
    url = urlsplit(value)
    production_host = 'api-production-6e8d.up.railway.app'
    loopback = url.hostname in ('localhost', '127.0.0.1', '::1')
    if (not url.hostname or url.username or url.password or url.query or url.fragment or
            url.path not in ('/api/v1', '/api/v1/') or
            not (url.scheme == 'https' or (environment == 'staging' and url.scheme == 'http' and loopback))):
        raise ValueError('Invalid API URL for deployment')
    if (environment == 'production') != (url.hostname == production_host):
        raise ValueError('API host belongs to the other environment')


def main():
    root = Path(os.environ['SRCROOT'])
    source = root / os.environ['MULTIVERSE_FIREBASE_PLIST']
    build = Path(os.environ['TARGET_BUILD_DIR'])
    info = plistlib.loads((build / os.environ['INFOPLIST_PATH']).read_bytes())
    firebase = plistlib.loads(source.read_bytes())
    validate(info, firebase)
    destination = build / os.environ['UNLOCALIZED_RESOURCES_FOLDER_PATH'] / 'GoogleService-Info.plist'
    shutil.copyfile(source, destination)
    print('Validated Firebase configuration for ' + info['MultiverseEnvironment'])


if __name__ == '__main__':
    main()

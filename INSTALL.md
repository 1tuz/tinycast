# Install Tinycast from the fork

Run this in Terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/1tuz/tinycast/main/Scripts/install.sh | /bin/bash
```

The script builds `main` with Xcode 26 or 27. If Tinycast already exists in `/Applications`, the script
replaces that copy in place and reuses its signing identity from Keychain. Otherwise, it installs to
`~/Applications/Tinycast.app`. Set `TINYCAST_INSTALL_DIR` to choose another install folder or
`TINYCAST_SIGNING_IDENTITY` to select another signing identity. It needs Git, Xcode 26 or 27 and a
persistent signing identity. It does not install packages or change system settings.

In-app updates check stable releases from `1tuz/tinycast`. Each update must be published with the
same signing identity used for this local build.

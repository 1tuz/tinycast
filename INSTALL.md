# Install Tinycast from the fork

Run this in Terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/1tuz/tinycast/main/Scripts/install.sh | /bin/bash
```

The script builds `main` with Xcode 26 and installs `~/Applications/Tinycast.app`. It uses the first
valid code-signing identity in Keychain. Set `TINYCAST_SIGNING_IDENTITY` before running the command
to select another identity. It needs Git, Xcode 26 and a persistent signing identity. It does not
install packages or change system settings.

In-app updates check stable releases from `1tuz/tinycast`. Each update must be published with the
same signing identity used for this local build.

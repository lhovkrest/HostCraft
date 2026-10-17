# Local CurseForge configuration

HostCraft reads CURSEFORGE_API_KEY at startup. Your local .env is ignored by Git and is not compiled into the app or included as a Flutter asset.

## Change the key

- In the app: open Mods & plugins, then the key icon (Change CurseForge API key). Save a new key, or select Use environment key to remove the saved override.
- From a file: edit CURSEFORGE_API_KEY in .env, then fully restart HostCraft. During flutter run, the project-root .env is read. For a desktop release, place .env beside hostcraft.exe.
- Android: enter the key in the app. The project-root .env is not bundled in the APK.

A saved in-app key overrides environment configuration. Without a saved key, priority is: process environment variable, .env in the HostCraft support directory, .env beside the desktop executable, then project-root .env in debug builds. Empty files fall through to the next source. Quoted and unquoted values are supported; dollar signs remain literal.

Use .env.example as a template. A local .env is a plaintext configuration file, not encrypted storage. Keep it out of shared archives.

## Required credential

Mod search uses https://api.curseforge.com/v1 and the x-api-key header. Supply a catalog API key with access to that service. The author upload API uses a separate X-Api-Token credential. A 403 means the catalog denied access; changing where the same token is stored cannot grant that permission.

HostCraft also sends the key to HTTPS forgecdn.net download hosts. It recalculates headers on redirects so a key is never forwarded to an unrelated host.

Official references:
- https://docs.curseforge.com/rest-api/
- https://support.curseforge.com/support/solutions/articles/9000208346
- https://blog.curseforge.com/introducing-api-key-authentication-for-curseforge-file-downloads/

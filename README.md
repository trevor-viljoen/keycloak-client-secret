# keycloak-client-secret
This script will pull the existing client_secret for a given Keycloak
client in a given realm or generate a new secret for the same. It was designed to
work with the Red Hat OpenShift Keycloak Operator, but could be reworked
to work with any Keycloak deployment. Please open an
[issue](https://github.com/trevor-viljoen/keycloak-client-secret/issues)
and/or a
[pull request](https://github.com/trevor-viljoen/keycloak-client-secret/pulls).

```bash
  keycloak_client_secret.sh Copyright (C) 2021 Trevor Viljoen <trevor.viljoen@gmail.com>

  This program comes with ABSOLUTELY NO WARRANTY; for details type keycloak_client_secret.sh --warranty,
  This is free software, and you are welcome to redistribute it under certain conditions;
  type keycloak_client_secret.sh --conditions for details.

  Options:
    -n, --namespace Keycloak Namespace
    -r, --realm Kecloak Realm Name
    -c, --client-id Keycloak Realm Client ID (name)
    -g, --generate Generate a new Keycloak Realm Client Secret
    -c, --conditions Display the conditions
    -w, --warranty Display the warranty

```

### Get Secret Example:
```bash
$ ./keycloak_client_secret.sh -n namespace -r realm -c example-client
1b2dc479-8fad-2cae-1f8c-9382ca8de93f
```

### Create New Secret Example:
```bash
$ ./keycloak_client_secret.sh -n namespace -r realm -c example-client --generate
a2bed938-2864-ac72-2d7f-528cde07f821
```

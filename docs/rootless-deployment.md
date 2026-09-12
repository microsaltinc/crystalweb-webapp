# Rootless deployment accounts

Each hosted environment uses one Linux account, SSH key and rootless Docker daemon
per repository. The currently provisioned VPS belongs to development.
The backend account is `cicd-user`; the webapp account is `cicd-webapp`. Neither
account has sudo permission or belongs to the `docker` group. Their home and
release directories have mode `0700`. Each repository's matching GitHub environment
contains only its own account's SSH key. Provision separate keys for the future
production VPS. Keep administrator keys out of GitHub.

The separate accounts prevent a webapp deployment from reading backend credentials,
mounting its image storage or controlling its containers. This is filesystem and
process isolation on a shared kernel; it does not provide separate-machine resource
or network isolation. Host nginx owns public TLS and proxies the two loopback ports.

## Administrator provisioning

Use an administrator only for packages, accounts, storage mounts, host nginx/TLS,
SSH policy and system services. Follow Docker's [rootless installation guide](https://docs.docker.com/engine/security/rootless/).
With Docker's official Ubuntu repository already configured:

```sh
sudo apt-get install docker-ce-rootless-extras uidmap dbus-user-session slirp4netns
```

Create each deployment account with its own home, group and non-overlapping ranges
of at least 65,536 subordinate IDs in `/etc/subuid` and `/etc/subgid`. Install a
different public SSH key in each account. Require public-key authentication and
disable SSH forwarding and PTY allocation for these two accounts. Preserve the
administrator account's SSH access.

```sh
sudo install -d -m 0700 -o cicd-user -g cicd-user /srv/crystalweb-backend
sudo install -d -m 0700 -o cicd-webapp -g cicd-webapp /srv/crystalweb-webapp
sudo chmod 0700 /home/cicd-user /home/cicd-webapp
sudo loginctl enable-linger cicd-user
sudo loginctl enable-linger cicd-webapp
```

Remove any deployment-account membership in the privileged `docker` group. End
old sessions and restart that account's user manager so no process retains the old
supplementary group. Do this before installing its rootless daemon.

On a fresh application VPS, inventory the system Docker daemon before stopping it.
Do not stop existing workloads or migrate their data implicitly. Once it has no
containers or volumes in use, disable and mask the privileged services:

```sh
sudo systemctl disable --now docker.service docker.socket containerd.service
sudo systemctl mask docker.service docker.socket containerd.service
```

The user daemons run their own containerd processes and do not need these system
services. Leave Ubuntu's AppArmor and unprivileged-user-namespace protections
enabled; the packaged rootless extras supply the supported integration.

## Work as each deployment account

Log in directly over SSH as the relevant account, then run without sudo:

```sh
dockerd-rootless-setuptool.sh install
systemctl --user enable --now docker
docker info --format '{{json .SecurityOptions}}'
```

The result must include `name=rootless`. Enable bounded logging in the account's
`~/.config/docker/daemon.json`, for example the `local` driver with `max-size` of
`20m` and `max-file` of `5`. Restart only that account's daemon after changing it.
Lingering keeps each user service available after logout and enables startup at boot.

Production activation uses `scripts/rootless-docker.sh` to select
`unix:///run/user/$(id -u)/docker.sock` and verify the server is rootless. It rejects
root callers and members of the privileged `docker` group. This selection remains
explicit when `DOCKER_CONFIG` points to temporary registry credentials; it never
falls back to `/var/run/docker.sock`. Backend production backup/restore uses the
same check. Development Docker configuration is independent of this policy.

## Backend image-volume ownership

Provision the actual image-volume mount and an empty data directory owned by the
backend deployment account. The existing initializer maps container UID/GID 10001
into that account's subordinate ID ranges. Do not set host ownership to literal
UID 10001 or make storage world-writable. Container root in this rootless daemon
maps to the unprivileged deployment account, not host root.

Preserve subordinate ID mappings across reinstallations. Changing them requires a
reviewed data-ownership migration. Use the backend's container-based backup and
restore commands for files owned by mapped IDs; the frontend account receives no
access to the mount.

After attaching the real volume, configure its persistent mount and an administrator
drop-in for the backend's `user@UID.service` with
`RequiresMountsFor=/mnt/crystalweb-storage` (use the actual UID and configured path).
This orders the user manager and its Docker daemon after the storage mount. The
deployment mount check and application marker remain required and fail closed if
the real filesystem is unavailable.

## Verification

Check each key with a fresh noninteractive SSH connection. Verify rootless Docker
can start containers, publish the service's loopback port and restart its containers
after a user-daemon restart. Check that each account is denied access to the other
account's release directory and Docker socket, to host root files and to sudo.
Test image-volume ownership, writes and recovery using disposable data before
using the provider's production volume. The shared host still needs monitoring,
backups and normal operating-system security updates.

`himmelblau-dev` is an R&D environment for
[himmelblau](https://github.com/himmelblau-idm/himmelblau).

# Development

The project is based on `Makefile` orchestration, and for the time being
requires Debian 13 (Trixie) user space in order to be usable. The generated
virtual machine image also runs Debian 13 (Trixie).

In order to list of all the available commands and their descriptions, run:

    make help

> **Note**: The build process (`make build`) requires `sudo` privileges
> for tasks like disk partitioning and bootstrapping Debian.

1.  **Dependencies**

    Install the required packages for building the VM image and managing it
    with libvirt.

    ```bash
    sudo apt install \
      make guestfish debootstrap qemu-utils ovmf swtpm-tools jq curl \
      libguestfs-tools virt-viewer virtinst libvirt-daemon-system libvirt-clients \
      python3
    ```

2.  **Environment**

    Copy the example environment file and fill in your Azure tenant details.
    You can also enable advanced Himmelblau features here.

    ```bash
    cp .env.example .env
    nano .env
    ```

    The following variables are used during image build:

    * `ENTRA_DOMAIN` – Primary Azure Entra ID domain used for sign-in
      (for example `example.onmicrosoft.com`). This is written to the
      `domains` setting in `/etc/himmelblau/himmelblau.conf`.
    * `ENTRA_APP_UUID` – Azure Entra ID application (client) ID Himmelblau should
      use for directory operations and token acquisition. This is written to
      the `app_id` setting in `/etc/himmelblau/himmelblau.conf`.
    * `ENTRA_GROUP_UUID` – Azure Entra ID group object ID whose members are
      allowed to log in to the demo VM. This is written to the
      `pam_allow_groups` setting in `/etc/himmelblau/himmelblau.conf`.
    * `HSM_TYPE` – Key storage mode for Himmelblau (for example
      `soft`, `tpm`, or `tpm_if_possible`).
    * `ENABLE_HELLO` – Controls whether Linux Hello PIN enrollment is enabled
      for users (`true` or `false`).

3.  **Building**

    ```bash
    make build
    ```

    This produces a QCOW2 disk image and UEFI firmware blobs in the `build/`
    directory.

4.  **Install libvirt domain**

    Define or update a libvirt VM using the built image:

    ```bash
    make install
    ```

    This will generate `build/himmelblau-demo.xml` and define a libvirt
    domain named `himmelblau-demo` with SPICE graphics, virtio GPU with GL,
    and a vTPM backed by `swtpm`. SSH is forwarded from the host port
    `10022` to the guest port `22` using libvirt's `passt` backend.

5.  **Run the Virtual Machine**

    Start the VM via `virsh` (or your preferred libvirt frontend):

    ```bash
    virsh start himmelblau-demo
    ```

    You can then connect using `virt-viewer`:

    ```bash
    virt-viewer --connect qemu:///system --wait himmelblau-demo
    ```

# Groups and permissions

Himmelblau requires an app to be created at the [Microsoft Azure
portal](https://portal.azure.com/) with the following permissions:

1. `GroupMember.Read.All`
2. `User.Read.All`

If `pam_allow_groups` is not set in `/etc/himmelblau/himmelblau.conf`
`himmelblaud-tasks` will deny any logging attempts and output the following
message:

    DEBUG 🐛 [debug]: Number of intersecting groups: 0
    DEBUG 🐛 [debug]: User has valid token: true

Himmelblau denies login unless Entra ID has a group created for it and
configured to the `pam_allow_groups` setting. New Entra ID groups can be created
at the [Microsoft Entra admin center](https://entra.microsoft.com/).

In the `.env` file the following settings can be used to define app and group
for the build:

1. `ENTRA_APP_UUID`: UUID of the app. This will be used to configure the global
   `app_id` setting in `/etc/himmelblau/himmelblau.conf`.
2. `ENTRA_GROUP_UUID`: UUID of the group. This will be used configure the
   `pam_allowed_groups` setting in `/etc/himmelblau/himmelblau.conf`.

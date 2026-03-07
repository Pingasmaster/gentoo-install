## gentoo-install

This is a personal fork of [oddlama/gentoo-install](https://github.com/oddlama/gentoo-install) with opinionated changes that may not suit everyone. Refer to the upstream project for the original documentation.

It provides a menuconfig-inspired TUI or a config file to set up a Gentoo system, supporting common disk layouts, file systems (ext4, btrfs, ZFS, bcachefs), LUKS, mdraid, EFI/BIOS boot, and systemd/OpenRC.

## Usage

Boot into an [Arch Linux](https://www.archlinux.org/download/) live ISO, then:

```bash
pacman -Sy git
git clone "https://github.com/Pingasmaster/gentoo-install"
cd gentoo-install
./configure
./install
```

Every option is explained in `gentoo.conf.example` and in the TUI help menus.
You will be asked to review partitioning before anything destructive happens.

**Note:** The default configuration includes my personal SSH public key in `ROOT_SSH_AUTHORIZED_KEYS`. If you are not me, you should replace it with your own key or set the variable to an empty string (`ROOT_SSH_AUTHORIZED_KEYS=""`) in the TUI or config file before installing.

If you need to chroot into an already installed system, mount your main drive under `/mnt` and run `./install --chroot /mnt`.

## Updating the kernel

By default the system uses `sys-kernel/gentoo-kernel-bin` with a dracut initramfs.
Set `KERNEL_TYPE=source` to build from source with `sys-kernel/gentoo-kernel` instead.

A convenience script `generate_initramfs.sh` is provided in `/boot/efi/` (EFI) or `/boot/bios/` (BIOS). Update procedure:

1. Emerge new kernel
2. `eselect kernel set <kver>`
3. Back up old kernel and initramfs
4. `generate_initramfs.sh <kver> <initrd_path>`
5. Copy new kernel into place

## References

* [Gentoo AMD64 Handbook](https://wiki.gentoo.org/wiki/Handbook:AMD64)
* [Upstream project](https://github.com/oddlama/gentoo-install)

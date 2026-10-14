# Troubleshooting

## `vagrant up` fails / VirtualBox errors

- Confirm VirtualBox and the matching Vagrant installation.
- On Apple Silicon, `ubuntu/jammy64` may need an alternative box or provider; use a supported combo for your host.
- Free disk space and disable conflicting hypervisors if VirtualBox cannot start VMs.

## IP not within allowed ranges (`10.10.0.10`)

VirtualBox 6.1.28+ only allows host-only / private networks in ranges listed in `/etc/vbox/networks.conf`. Default is often `192.168.56.0/21`, so this lab’s `10.10.0.0/24` fails with:

```text
The IP address configured for the host-only network is not within the allowed ranges.
  Address: 10.10.0.10
  Ranges: 192.168.56.0/21, fe80::/10
```

Fix on the **host** (not inside a guest):

```bash
sudo mkdir -p /etc/vbox
printf '%s\n' '* 10.10.0.0/24' '* 192.168.56.0/21' | sudo tee /etc/vbox/networks.conf
```

Then re-run `make create`.

## `AMD-V is being used by another hypervisor` / `VERR_SVM_IN_USE`

On Linux hosts, the KVM kernel modules (`kvm_amd` / `kvm_intel`) take exclusive hardware virtualization. VirtualBox then fails at boot with `VERR_SVM_IN_USE`.

Check:

```bash
lsmod | grep kvm
```

Unload KVM (safe if no QEMU/libvirt VMs are running; Docker containers usually do not need KVM):

```bash
sudo modprobe -r kvm_amd 2>/dev/null || sudo modprobe -r kvm_intel 2>/dev/null
sudo modprobe -r kvm
```

If unload fails because VirtualBox modules hold `kvm`, stop VMs and reload VirtualBox after:

```bash
cd infrastructure && vagrant halt
sudo modprobe -r vboxnetadp vboxnetflt vboxdrv
sudo modprobe -r kvm_amd 2>/dev/null || sudo modprobe -r kvm_intel 2>/dev/null
sudo modprobe -r kvm
sudo modprobe vboxdrv
```

Optional — keep KVM from loading after reboot (VirtualBox-only host):

```bash
echo -e 'blacklist kvm_amd\nblacklist kvm_intel\nblacklist kvm' | sudo tee /etc/modprobe.d/blacklist-kvm-for-virtualbox.conf
```

Then re-run `make create`.

## Synced folder `/opt/automation-alchemy` missing inside the guest

Provisioning expects the project tree synced to `/opt/automation-alchemy`. If Guest Additions fail:

```bash
cd infrastructure
vagrant vbguest  # if plugin installed
# or: vagrant reload --provision
```

## `devops` SSH: Permission denied (publickey)

1. Confirm key exists: `ls -l keys/id_ed25519 keys/id_ed25519.pub`
2. Recreate and re-provision: `make reset`
3. Inside guest via `vagrant ssh <name>`: check `/home/devops/.ssh/authorized_keys`

## Cannot run `vagrant ssh` after hardening

NAT Match must allow `vagrant` from `10.0.2.0/24` (see `config/sshd_config`). Re-run provision:

```bash
cd infrastructure
vagrant provision
```

## sudo asks for a password (expected)

Passwordless sudo was removed on purpose. Lab password: `devops`.

```bash
sudo -n true   # should fail
sudo whoami    # prompt, then root
```

## UFW blocks SSH from host

UFW must allow `22/tcp` before enable. From VirtualBox console / `vagrant ssh`:

```bash
sudo ufw allow 22/tcp
sudo ufw --force enable
```

## Ping works but SSH fails

- Wait for provision to finish (`make status`, then `vagrant provision` if needed).
- Confirm `sshd` is running: `sudo systemctl status ssh`
- Confirm private IP is up: `ip a`

## `make verify` / umask check fails

Login shells must load `/etc/profile.d/zz-secure-umask.sh`. Check:

```bash
ssh -i keys/id_ed25519 devops@10.10.0.10 'bash -lc umask'
```

Expect `0027`. Re-provision if the profile snippet is missing.

## Wrong hostname or IP after editing YAML

YAML / `config/hosts` changes require recreate:

```bash
make reset
```

## Destroyed VMs but VirtualBox still shows ghosts

```bash
make destroy
# Then remove leftover VMs from VirtualBox Manager if needed
# Group folder: /Automation-Alchemy
```

## Known issues

- First `vagrant up` downloads the Ubuntu box and can take a long time.
- Low-memory hosts: five VMs (~3.5 GB combined guest RAM) may need closing other apps.
- Netdata `:19999` is opened only after `make stretch-monitor` (lab CIDR). The portfolio dashboard binds loopback `127.10.10.10:3030` on the host — it is not a guest UFW rule.

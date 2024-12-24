{
  "product": {
    "id": "SLES_16.0"
  },
  "user": {
    "fullName": "Bernhard M. Wiedemann",
    "password": "$6$vYbbuJ9WMriFxGHY$gQ7shLw9ZBsRcPgo6/8KmfDvQ/lCqxW8/WnMoLCoWGdHO6Touush1nhegYfdBbXRpsQuy/FTZZeg7gQL50IbA/",
    "hashedPassword": true,
    "userName": "bernhard"
  },
  "root": {
    "password": "$6$vYbbuJ9WMriFxGHY$gQ7shLw9ZBsRcPgo6/8KmfDvQ/lCqxW8/WnMoLCoWGdHO6Touush1nhegYfdBbXRpsQuy/FTZZeg7gQL50IbA/",
    "hashedPassword": true
  },
  "scripts": {
    "post": [
      {
        "name": "enable root login",
        "chroot": true,
        "body": |||
          #!/usr/bin/env bash
          zypper rm openssh-server-config-rootlogin
          echo 'PermitRootLogin yes' > /etc/ssh/sshd_config.d/root.conf
          sed -i 's/GRUB_TIMEOUT.*$/GRUB_TIMEOUT=-1/' /etc/default/grub
          for i in `sed -n '/set timeout=/=' /boot/grub2/grub.cfg |sed 1d`
              do sed -i "$i"'s/set timeout=.$/set timeout=-1/' /boot/grub2/grub.cfg
          done
        |||
      }
    ]
  }
}

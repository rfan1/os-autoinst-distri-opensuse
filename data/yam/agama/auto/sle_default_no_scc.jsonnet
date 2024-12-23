{
  "product": {
    "id": "SLES_16.0"
  },
  "user": {
    "fullName": "Bernhard M. Wiedemann",
    "password": "nots3cr3t",
    "userName": "bernhard"
  },
  "root": {
    "password": "nots3cr3t"
  },
  "scripts": {
    "pre": [
      {
        "name": "wipefs",
        "body": |||
          #!/usr/bin/env bash
          wipefs -fa /dev/sda
        |||
      }
    ],
    "post": [
      {
        "name": "enable root login",
        "chroot": true,
        "body": |||
          #!/usr/bin/env bash
          echo 'PermitRootLogin yes' > /etc/ssh/sshd_config.d/root.conf
        |||
      }
    ]
  }
}

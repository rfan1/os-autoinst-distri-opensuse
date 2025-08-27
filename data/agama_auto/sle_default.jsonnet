{
  product: {
    id: '{{AGAMA_PRODUCT_ID}}',
    registrationCode: '{{SCC_REGCODE}}',
    addons: [
      {
        id: 'PackageHub',
      }
    ]
  },
  bootloader: {
    stopOnBootMenu: true,
  },
  user: {
    fullName: 'Bernhard M. Wiedemann',
    password: '$6$vYbbuJ9WMriFxGHY$gQ7shLw9ZBsRcPgo6/8KmfDvQ/lCqxW8/WnMoLCoWGdHO6Touush1nhegYfdBbXRpsQuy/FTZZeg7gQL50IbA/',
    hashedPassword: true,
    userName: 'bernhard'
  },
  root: {
    password: '$6$vYbbuJ9WMriFxGHY$gQ7shLw9ZBsRcPgo6/8KmfDvQ/lCqxW8/WnMoLCoWGdHO6Touush1nhegYfdBbXRpsQuy/FTZZeg7gQL50IbA/',
    hashedPassword: true
  },
  questions: {
    policy: 'auto',
    answers: [
      {
        answer: 'Trust',
        class: 'software.import_gpg',
        data: {
          fingerprint: 'BF3F 9A67 D3A2 FF98 A73F 5E07 488C 583D 287A 0027'
        }
      }
    ]
  },
  scripts: {
    post: [
      {
        name: 'enable sshd',
        chroot: true,
        content: |||
          #!/usr/bin/env bash
          systemctl enable sshd
        |||
      }
    ]
  }
}

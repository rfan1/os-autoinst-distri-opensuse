## Copyright 2024 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

# Summary: Wait for unattended installation to finish,
# reboot and reach login prompt.
# Maintainer: QE Installation and Migration (QE Iam) <none@suse.de>

use Mojo::Base 'Yam::Agama::agama_base';

use testapi;
use Utils::Architectures qw(is_aarch64 is_s390x is_ppc64le);
use Utils::Backends qw(is_pvm is_svirt is_hyperv);
use power_action_utils 'power_action';
use version_utils qw(is_vmware is_leap);

sub run {
    my $self = shift;
    # VNC/Web console gets stuck sporadically on aarch64, see
    # https://bugzilla.suse.com/show_bug.cgi?id=1267026.
    # We can switch the console as a workaround.
    select_console 'install-shell' if is_aarch64;
    select_console 'installation';
    my $reboot_page = $testapi::distri->get_reboot();
    $reboot_page->expect_is_shown();

    $self->upload_agama_logs() unless is_hyperv();

    (is_s390x() || (is_ppc64le() && check_var("DESKTOP", "textmode")) || is_pvm() || is_vmware()) ?
      # reboot via console
      power_action('reboot', keepconsole => 1, first_reboot => 1) :
      # graphical reboot
      $reboot_page->reboot();
}

1;

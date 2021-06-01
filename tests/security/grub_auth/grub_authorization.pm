# Copyright (C) 2021 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, see <http://www.gnu.org/licenses/>.
#
# Summary: grub2 supports restricting access to boot menu entries when
#          building their images/appliances,so that only specified
#          users can boot selected menu entries.
#
# Test steps: 1) Create custom grub config file with users/passwords to
#                authenticate the access of grub options at boot loader screen
#             2) Reboot the OS to make sure both super user and maintain user
#                can access into the corresponding grub menu entry
#             3) Wrong user/password is not able access the grub
#
# Maintainer: rfan1 <richard.fan@suse.com>
# Tags: poo#81721, tc#1768659

use base 'opensusebasetest';
use strict;
use warnings;
use testapi;
use base 'consoletest';
use utils 'zypper_call';

sub run {
    my $self = shift;
    $self->select_serial_terminal;
    zypper_call("in 389-ds sssd sssd-ldap 'openssl(cli)'");
    assert_script_run("/usr/bin/openssl rehash /etc/openldap");
}

sub test_flags {
    return {fatal => 1};
}

1;

# Copyright 2020-2021 SUSE LLC
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

# Summary: Module to set up the environment for using libyui REST API with the
# installer, which requires enabling libyui-rest-api packages.

# Maintainer: QA SLE YaST team <qa-sle-yast@suse.de>

use strict;
use warnings;
use base "installbasetest";
use Utils::Backends;
use Utils::Architectures;
use testapi;
use YuiRestClient;

sub run {
    my $app = YuiRestClient::get_app(installation => 1, timeout => 60, interval => 1);
    my $port = $app->get_port();
    record_info('SERVER', "Used host for libyui: " . $app->get_host());
    record_info('PORT', "Used port for libyui: " . $port);

    if (is_ssh_installation) {
        my $cmd = '';
        if (is_s390x) {
            if (is_svirt) {
                $cmd = 'TERM=linux ';
            }
            elsif (get_var('BACKEND') eq 's390x') {
                $cmd = 'QT_XCB_GL_INTEGRATION=none ';
                record_soft_failure('bsc#1142040');
            }
        }
        $cmd .= YuiRestClient::get_yui_params_string($port) . " yast.ssh";
        enter_cmd($cmd);
    }
    $app->check_connection(timeout => 500, interval => 10);
}

1;

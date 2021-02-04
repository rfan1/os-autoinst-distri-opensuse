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
# Summary: Implement & Integrate 389ds + sssd test case into openQA
#
# Maintainer: rfan1 <richard.fan@suse.com>
# Tags: poo#81763

use base 'consoletest';
use testapi;
use strict;
use warnings;
use utils;
use lockapi;
use mmapi 'wait_for_children';
use utils 'zypper_call';
use Utils::Systemd qw(systemctl disable_and_stop_service);
use utils 'script_run_interactive';
use mm_network qw(setup_static_mm_network configure_hostname);

sub run {
        if (get_var('IS_MM_389DS')) {
        barrier_create 'SETUP_DONE',               2;
        barrier_create 'MM_NETWORK_COMPLETED',     2;
        barrier_create '389DS_INSTALL_COMPLETED',  2;
        barrier_create 'BASIC_CONFIGURATION_DONE', 2;
        barrier_create 'CREATE_USER_COMPLETED',    2;
        barrier_create 'TEST_COMPLETED',           2;
    }	

    my $self = shift;
    $self->select_serial_terminal;
    barrier_wait 'SETUP_DONE';

    # Setup /etc/hosts and configure static ip and hostname, disable firewalld
    my ($local_ip, $remote_ip, $local_name, $remote_name);
    if (get_var('IS_MM_389DS')) {
        $local_ip  = '10.0.2.111';
        $remote_ip = '10.0.2.112';
        $local_name = '389ds';
        $remote_name = '389dc';
    } else {
        $local_ip  = '10.0.2.112';
        $remote_ip = '10.0.2.111';
        $local_name = '389dc';
        $remote_name = '389ds';
    }
    assert_script_run("echo '$local_ip $local_name.example.com $local_name' >> /etc/hosts");
    assert_script_run("echo '$remote_ip $remote_name.example.com $remote_name' >> /etc/hosts");
    disable_and_stop_service("firewalld");
    setup_static_mm_network("$local_ip/24");
    systemctl("restart wicked");
    configure_hostname("$local_name");
    barrier_wait('MM_NETWORK_COMPLETED');

    # Install 389-ds and create an server instance
    zypper_call("in 389-ds");
    barrier_wait('389DS_INSTALL_COMPLETED');

    # Install 389-ds and create an server instance
    if (get_var('IS_MM_389DS')) {
        zypper_call("in 389-ds");
        assert_script_run("wget --quiet " . data_url("389ds/instance.inf") . " -O /tmp/instance.inf");
        assert_script_run("dscreate from-file /tmp/instance.inf");
        validate_script_output("dsctl localhost status" sub { m/instance 'Localhost' is running/ });

        # Configure CA Certificates for TLS
        my $ca_dir     = '/etc/openldap/ssl';
        my $inst_ca_dir= '/etc/dirsrv/slapd-localhost';
        assert_script_run("wget --quiet " . data_url("389ds/tls_cert.sh") . " -O /tmp/tls_cert.sh");
        assert_script_run("bash /tmp/tls_cert.sh $local_name $ca_dir");
        assert_script_run("certutil -D -d $inst_ca_dir -n Server-Cert");
        assert_script_run("certutil -D -d $inst_ca_dir -n Self-Signed-CA");
        assert_script_run("dsctl localhost tls import-server-key-cert $ca_dir/server.pem $ca_dir/server.key");
        assert_script_run("dsctl localhost tls import-ca $ca_dir/myca.pem myca");
        assert_script_run("cp $ca_dir/myca.pem $inst_ca_dir/ca.crt");
        systemctl("restart dirsrv@localhost.service");
    } else {
         zypper_call("in sssd");
         disable_and_stop_service("nscd", ignore_failure => 1);
    } 
    barrier_wait 'BASIC_CONFIGURATION_DONE';
    
    # Create user and group
    my $ldap_user = 'wilber';
    my $ldap_passwd = 'pw_389ds';
    my $ldap_group = 'server_admins';
    my $uid = '1003';
    my $gid = '1003';
    my $display_name = 'Wilber Fox';

    if (get_var('IS_MM_389DS')) {
        assert_script_run("dsidm localhost user create --uid $ldap_user --cn $ldap_user --displayName '$display_name' --uidNumber $uid --gidNumber $gid --homeDirectory /home/$ldap_user");
        script_run_interactive(
            "dsidm localhost account reset_password uid=$ldap_user,ou=people,dc=example,dc=com",
            [
                {
                    prompt => qr/Enter new password.*/m,
                    string => "$ldap_passwd\n",
                },
                {
                    prompt => qr/CONFIRM.*/m,
                    string => "$ldap_passwd\n",
                },
            ],
            60
        );
        script_run_interactive(
            "dsidm localhost group create",
            [
                {
                    prompt => qr/Enter value.*/m,
                    string => "$ldap_group\n",
                },
            ],
            60
        );
        assert_script_run("dsidm localhost group add_member $ldap_group uid=$ldap_user,ou=people,dc=example,dc=com");
    } 
    barrier_wait('CREATE_USER_COMPLETED');

    # Verify sssd authentication on sssd client
    if (get_var('IS_MM_389DS')) {
        assert_script_run("dsidm localhost client_config sssd.conf $ldap_group > /tmp/sssd.conf");
        assert_script_run("sed -i '1,2d' /tmp/sssd.conf");
        assert_script_run("sed -i 's/^ldap_uri =.*\$/ldap_uri = ldaps:\/\/\$local_name.example.com/' /tmp/sssd.conf");

        exec_and_insert_password("scp -o StrictHostKeyChecking=no /tmp/sssd.conf root\@$remote_name:/tmp");
        exec_and_insert_password("scp -o StrictHostKeyChecking=no /etc/dirsrv/slapd-localhost/ca.crt root\@$remote_name:/tmp");
        mutex_create 'server_ready';
    } else {
        mutex_unlock 'server_ready';
        assert_script_run("sed -i '1,2d' /tmp/sssd.conf"); 
        my $tls_dir = '/etc/openldap/certs';
        assert_script_run("mkdir -p $tls_dir");
        assert_script_run("mv /tmp/ca.crt $tls_dir");
        assert_script_run("/usr/bin/openssl rehash $tls_dir");
        assert_script_run("cp /etc/sssd/sssd.conf /tmp/sssd.conf.back");
        assert_script_run("cat /tmp/sssd.conf > /etc/sssd/sssd.conf");
        assert_script_run("sed -i '/^passwd.*/ s/\$/ sss/' /etc/nsswitch.conf");
        assert_script_run("sed -i '/^group.*/ s/\$/ sss/' /etc/nsswitch.conf");
        assert_script_run("sed -i '/^shadow.*/ s/\$/ sss/' /etc/nsswitch.conf");
        assert_script_run("pam-config -a -sss");
        assert_script_run("pam-config -q -sss");
        systemctl("enable sssd");
        systemctl("start sssd");
        assert_script_run("id $ldap_user | grep $uid");
    }
    barrier_wait('TEST_COMPLETED');
    
    # Finish job
    wait_for_children if (get_var('IS_MM_389DS'));
}

1;

package vagrant;
use testapi;
use strict;
use warnings;
use utils;

our @ISA = qw(Exporter);
our @EXPORT = qw(setup_vagrant_libvirt setup_vagrant_virtualbox run_vagrant_cmd);

# - install vagrant and vagrant-libvirt
# - launch the required daemons
sub setup_vagrant_libvirt {
    select_console('root-console');

    zypper_call("in vagrant vagrant-libvirt");
    systemctl("start libvirtd");
    assert_script_run("usermod -a -G libvirt bernhard");
}

# - install vagrant and virtualbox
# - launch the required daemons
sub setup_vagrant_virtualbox {
    select_console('root-console');

    zypper_call("in vagrant virtualbox");
    systemctl("start vboxdrv");
    systemctl("start vboxautostart-service");
    assert_script_run("usermod -a -G vboxusers bernhard");
}

sub run_vagrant_cmd {
    my ($cmd, %args) = @_;

    my $logfile = 'vagrant_cmd.log';
    my $ret = script_run("VAGRANT_LOG=DEBUG vagrant $cmd 2> $logfile", %args);
    return undef if $ret == 0;
    upload_logs($logfile);
    die "'vagrant $cmd' failed with $ret";
}

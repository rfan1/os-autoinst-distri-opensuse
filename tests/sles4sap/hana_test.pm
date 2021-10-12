# SUSE's SLES4SAP openQA tests
#
# Copyright 2018 SUSE LLC
#
# Copying and distribution of this file, with or without modification,
# are permitted in any medium without royalty provided the copyright
# notice and this notice are preserved.  This file is offered as-is,
# without any warranty.

# Summary: Checks HANA installation as performed by sles4sap/wizard_hana_install
# Requires: sles4sap/wizard_hana_install, ENV variables INSTANCE_SID
# Maintainer: Ricardo Branco <rbranco@suse.de>

use base "sles4sap";
use strict;
use warnings;
use testapi;

sub run {
    my ($self) = @_;
    my $ps_cmd = $self->set_ps_cmd('HDB');

    $self->select_serial_terminal;

    # First, upload the installation logs if we are doing AutoYaST test
    # NOTE: done here because AutoYaST part is not HANA specific
    $self->upload_hana_install_log if get_var('AUTOYAST');

    # Check the memory/disk configuration
    assert_script_run 'clear ; free -m';
    assert_script_run 'lvs -ao +devices vg_hana';
    assert_script_run 'df -k | grep vg_hana';
    save_screenshot;

    # The SAP Admin was set in sles4sap/wizard_hana_install
    my $sid = get_required_var('INSTANCE_SID');
    my $instance_id = get_required_var('INSTANCE_ID');
    my $sapadm = $self->set_sap_info($sid, $instance_id);

    # Test PIDs max, as SAP as some prerequisites on this and change for SAP user
    $self->test_pids_max;
    $self->user_change;

    # Check HDB with a database query
    my $hdbsql = "hdbsql -j -d $sid -u SYSTEM -i $instance_id -p $sles4sap::instance_password";
    my $output = script_output "$hdbsql 'SELECT * FROM DUMMY'";
    die "hdbsql: failed to query the dummy table\n\n$output" unless ($output =~ /1 row selected/);

    # Run NVDIMM tests if in that scenario
    if (get_var('NVDIMM')) {
        $output = script_output "$hdbsql \"SELECT * FROM M_INIFILE_CONTENTS where file_name = 'global.ini' and section = 'persistence' and key = 'basepath_persistent_memory_volumes'\"";
        my $pmempath = get_var('HANA_PMEM_BASEPATH', "/hana/pmem/$sid");
        my $nvddevs = get_var('NVDIMM_NAMESPACES_TOTAL', 2);
        foreach my $i (0 .. ($nvddevs - 1)) {
            die "hdbsql: HANA not configured with NVDIMM\n\n$output" unless ($output =~ /pmem$i/);
            assert_script_run "grep -q -w pmem$i /hana/shared/$sid/global/hdb/custom/config/global.ini";
            assert_script_run "ls $pmempath/pmem$i";
            assert_script_run "test -n \"\$(ls $pmempath/pmem$i)\"";
        }
    }

    # Do the stop/start tests
    $self->test_version_info;
    $self->test_instance_properties;
    $self->test_stop;
    $self->test_start;

    assert_script_run "HDB info";
    my $ver_info = script_output 'HDB version';
    record_info 'HANA Version', $ver_info;

    # Disconnect SAP account
    $self->reset_user_change;
}

1;

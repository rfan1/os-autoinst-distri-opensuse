# SUSE's openQA tests
#
# Copyright 2022 SUSE LLC
# SPDX-License-Identifier: FSFAP
#
# Summary: Functions to use qe-sap-deployment project
# Maintainer: QE-SAP <qe-sap@suse.de>

## no critic (RequireFilenameMatchesPackage);

=encoding utf8

=head1 NAME

    qe-sap-deployment test lib

=head1 COPYRIGHT

    Copyright 2022 SUSE LLC
    SPDX-License-Identifier: FSFAP

=head1 AUTHORS

    QE SAP <qe-sap@suse.de>

=cut

package qesapdeployment;

use strict;
use warnings;
use Carp qw(croak);
use Mojo::JSON qw(decode_json);
use YAML::PP;
use List::Util qw(any);
use utils qw(file_content_replace);
use publiccloud::utils qw(get_credentials);
use mmapi 'get_current_job_id';
use testapi;
use Exporter 'import';

my @log_files = ();

# Terraform requirement
#  terraform/azure/infrastructure.tf  "azurerm_storage_account" "mytfstorageacc"
# stdiag<PREFID><JOB_ID> can only consist of lowercase letters and numbers,
# and must be between 3 and 24 characters long
use constant QESAPDEPLOY_PREFIX => 'qesapdep';
use constant QESAPDEPLOY_VENV => '/tmp/exec_venv';

our @EXPORT = qw(
  qesap_create_folder_tree
  qesap_pip_install
  qesap_upload_logs
  qesap_get_deployment_code
  qesap_get_inventory
  qesap_get_nodes_number
  qesap_get_terraform_dir
  qesap_prepare_env
  qesap_execute
  qesap_yaml_replace
  qesap_ansible_cmd
  qesap_ansible_script_output
  qesap_create_ansible_section
  qesap_create_aws_credentials
  qesap_create_aws_config
  qesap_remote_hana_public_ips
  qesap_wait_for_ssh
  qesap_cluster_log_cmds
  qesap_cluster_logs
  qesap_get_vnet
  qesap_get_az_resource_group
  qesap_calculate_az_address_range
  qesap_az_vnet_peering
  qesap_delete_az_peering
);

=head1 DESCRIPTION

    Package with common methods and default or constant  values for qe-sap-deployment

=head2 Methods


=head3 qesap_get_file_paths

    Returns a hash containing file paths for config files
=cut

sub qesap_get_file_paths {
    my %paths;
    $paths{qesap_conf_filename} = get_required_var('QESAP_CONFIG_FILE');
    $paths{deployment_dir} = get_var('QESAP_DEPLOYMENT_DIR', '/root/qe-sap-deployment');
    $paths{terraform_dir} = get_var('PUBLIC_CLOUD_TERRAFORM_DIR', $paths{deployment_dir} . '/terraform');
    $paths{qesap_conf_trgt} = $paths{deployment_dir} . '/scripts/qesap/' . $paths{qesap_conf_filename};
    $paths{qesap_conf_src} = data_url('sles4sap/qe_sap_deployment/' . $paths{qesap_conf_filename});
    return (%paths);
}

=head3 qesap_create_folder_tree

    Create all needed folders
=cut

sub qesap_create_folder_tree {
    my %paths = qesap_get_file_paths();
    assert_script_run("mkdir -p $paths{deployment_dir}", quiet => 1);
}

=head3 qesap_get_variables

    Scans yaml config for '%OPENQA_VARIABLE%' placeholders and searches for values in OpenQA defined variables.
    Returns hash with openqa variable key/value pairs.
=cut

sub qesap_get_variables {
    my %paths = qesap_get_file_paths();
    my $yaml_file = $paths{'qesap_conf_src'};
    my %variables;
    my $cmd = join(' ',
        'curl -s -fL', $yaml_file, '|',
        'grep -v', "'#'", '|',
        'grep -oE %[A-Z0-9_]*%', '|',
        'sed s/%//g');

    for my $variable (split(" ", script_output($cmd))) {
        $variables{$variable} = get_required_var($variable);
    }
    return \%variables;
}

=head3 qesap_create_ansible_section

    Writes "ansible" section into yaml config file.
    $args{ansible_section} defines section(key) name.
    $args{section_content} defines content of names section.
        Example:
            @playbook_list = ("pre-cluster.yaml", "cluster_sbd_prep.yaml");
            qesap_create_ansible_section(ansible_section=>'create', section_content=>\@playbook_list);

=cut

sub qesap_create_ansible_section {
    my (%args) = @_;
    my $ypp = YAML::PP->new;
    my $section = $args{ansible_section} // 'no_section_provided';
    my $content = $args{section_content} // {};
    my %paths = qesap_get_file_paths();
    my $yaml_config_path = $paths{qesap_conf_trgt};

    assert_script_run("test -e $yaml_config_path", fail_message => "Yaml config file '$yaml_config_path' does not exist.");

    my $raw_file = script_output("cat $yaml_config_path");
    my $yaml_data = $ypp->load_string($raw_file);

    $yaml_data->{ansible}{$section} = $content;

    # write into file
    my $yaml_dumped = $ypp->dump_string($yaml_data);
    save_tmp_file($paths{qesap_conf_filename}, $yaml_dumped);
    assert_script_run('curl -v -fL ' . autoinst_url . "/files/" . $paths{qesap_conf_filename} . ' -o ' . $paths{qesap_conf_trgt});
    return;
}

=head3 qesap_pip_install

  Install all Python requirements of the qe-sap-deployment in a dedicated virtual environment
=cut

sub qesap_pip_install {
    assert_script_run("python3.10 -m venv " . QESAPDEPLOY_VENV . " && source " . QESAPDEPLOY_VENV . "/bin/activate");
    enter_cmd 'pip3.10 config --site set global.progress_bar off';
    my $pip_ints_cmd = 'pip3.10 install --no-color --no-cache-dir ';
    my $pip_install_log = '/tmp/pip_install.txt';
    my %paths = qesap_get_file_paths();

    push(@log_files, $pip_install_log);
    record_info("QESAP repo", "Installing pip requirements");
    assert_script_run(join(' ', $pip_ints_cmd, '-r', $paths{deployment_dir} . '/requirements.txt | tee -a', $pip_install_log), 360);
    script_run("deactivate");
}

=head3 qesap_upload_logs

    qesap_upload_logs([failok=1])

    Collect and upload logs present in @log_files.

=over 1

=item B<FAILOK> - used as failok for the upload_logs. continue even in case upload fails

=back
=cut

sub qesap_upload_logs {
    my (%args) = @_;
    my $failok = $args{failok};
    record_info("Uploading logfiles", join("\n", @log_files));
    while (my $file = pop @log_files) {
        upload_logs($file, failok => $failok);
    }
}

=head3 qesap_get_deployment_code

    Get the qe-sap-deployment code
=cut

sub qesap_get_deployment_code {
    my $official_repo = 'github.com/SUSE/qe-sap-deployment';
    my $qesap_git_clone_log = '/tmp/git_clone.txt';
    my %paths = qesap_get_file_paths();

    record_info("QESAP repo", "Preparing qe-sap-deployment repository");

    enter_cmd "cd " . $paths{deployment_dir};
    push(@log_files, $qesap_git_clone_log);

    # Script from a release
    if (get_var('QESAP_INSTALL_VERSION')) {
        record_info("WARNING", "QESAP_INSTALL_GITHUB_REPO will be ignored") if (get_var('QESAP_INSTALL_GITHUB_REPO'));
        record_info("WARNING", "QESAP_INSTALL_GITHUB_BRANCH will be ignored") if (get_var('QESAP_INSTALL_GITHUB_BRANCH'));
        my $ver_artifact = 'v' . get_var('QESAP_INSTALL_VERSION') . '.tar.gz';

        my $curl_cmd = "curl -v -fL https://$official_repo/archive/refs/tags/$ver_artifact -o$ver_artifact";
        assert_script_run("set -o pipefail ; $curl_cmd | tee " . $qesap_git_clone_log, quiet => 1);

        my $tar_cmd = "tar xvf $ver_artifact --strip-components=1";
        assert_script_run($tar_cmd);
    }
    else {
        # Get the code for the qe-sap-deployment by cloning its repository
        assert_script_run('git config --global http.sslVerify false', quiet => 1) if get_var('QESAP_INSTALL_GITHUB_NO_VERIFY');
        my $git_branch = get_var('QESAP_INSTALL_GITHUB_BRANCH', 'main');

        my $git_repo = get_var('QESAP_INSTALL_GITHUB_REPO', $official_repo);
        my $git_clone_cmd = 'git clone --depth 1 --branch ' . $git_branch . ' https://' . $git_repo . ' ' . $paths{deployment_dir};
        assert_script_run("set -o pipefail ; $git_clone_cmd  2>&1 | tee $qesap_git_clone_log", quiet => 1);
    }
    # Add symlinks for different provider directory naming between OpenQA and qesap-deployment
    assert_script_run("ln -s " . $paths{terraform_dir} . "/aws " . $paths{terraform_dir} . "/ec2");
    assert_script_run("ln -s " . $paths{terraform_dir} . "/gcp " . $paths{terraform_dir} . "/gce");
}

=head3 qesap_yaml_replace

    Replaces yaml config file variables with parameters defined by OpenQA testode, yaml template or yaml schedule.
    Openqa variables need to be added as a hash with key/value pair inside %run_args{openqa_variables}.
    Example:
        my %variables;
        $variables{HANA_SAR} = get_required_var("HANA_SAR");
        $variables{HANA_CLIENT_SAR} = get_required_var("HANA_CLIENT_SAR");
        qesap_yaml_replace(openqa_variables=>\%variables);
=cut

sub qesap_yaml_replace {
    my (%args) = @_;
    my $variables = $args{openqa_variables};
    my %replaced_variables = ();
    my %paths = qesap_get_file_paths();
    push(@log_files, $paths{qesap_conf_trgt});

    for my $variable (keys %{$variables}) {
        $replaced_variables{"%" . $variable . "%"} = $variables->{$variable};
    }
    file_content_replace($paths{qesap_conf_trgt}, %replaced_variables);
    qesap_upload_logs();
}

=head3 qesap_execute

    qesap_execute(cmd => $qesap_script_cmd [, verbose => 1, cmd_options => $cmd_options] );
    cmd_options - allows to append additional qesap.py commans arguments like "qesap.py terraform -d"
        Example:
        qesap_execute(cmd => 'terraform', cmd_options => '-d') will result in:
        qesap.py terraform -d

    Execute qesap glue script commands. Check project documentation for available options:
    https://github.com/SUSE/qe-sap-deployment
    Test only returns execution result, failure has to be handled by calling method.
=cut

sub qesap_execute {
    my (%args) = @_;
    croak 'Missing mandatory cmd argument' unless $args{cmd};

    my $verbose = $args{verbose} ? "--verbose" : "";
    my %paths = qesap_get_file_paths();
    $args{cmd_options} ||= '';

    my $exec_log = "/tmp/qesap_exec_$args{cmd}";
    $exec_log .= "_$args{cmd_options}" if ($args{cmd_options});
    $exec_log .= '.log.txt';
    $exec_log =~ s/[-\s]+/_/g;
    # activate virtual environment
    script_run("source " . QESAPDEPLOY_VENV . "/bin/activate");

    my $qesap_cmd = join(' ', 'python3.10', $paths{deployment_dir} . '/scripts/qesap/qesap.py',
        $verbose,
        '-c', $paths{qesap_conf_trgt},
        '-b', $paths{deployment_dir},
        $args{cmd},
        $args{cmd_options},
        '|& tee -a',
        $exec_log
    );

    push(@log_files, $exec_log);
    record_info('QESAP exec', "Executing: \n$qesap_cmd");
    my $exec_rc = script_run($qesap_cmd, timeout => $args{timeout});
    qesap_upload_logs();
    # deactivate virtual environment
    script_run("deactivate");
    return $exec_rc;
}

=head3 qesap_get_inventory

    Return the path of the generated inventory
=cut

sub qesap_get_inventory {
    my ($provider) = @_;
    my %paths = qesap_get_file_paths();
    return "$paths{deployment_dir}/terraform/" . lc $provider . '/inventory.yaml';
}

=head3 qesap_get_nodes_number

Get the number of cluster nodes from the inventory.yaml
=cut

sub qesap_get_nodes_number {
    my $inventory = qesap_get_inventory(get_required_var('PUBLIC_CLOUD_PROVIDER'));
    my $yp = YAML::PP->new();

    my $inventory_content = script_output("cat $inventory");
    my $parsed_inventory = $yp->load_string($inventory_content);
    my $num_hosts = 0;
    while ((my $key, my $value) = each(%{$parsed_inventory->{all}->{children}})) {
        $num_hosts += keys %{$value->{hosts}};
    }
    return $num_hosts;
}

=head3 qesap_get_terraform_dir

    Return the path used by the qesap script as -chdir argument for terraform
    It is useful if test would like to call terraform
=cut

sub qesap_get_terraform_dir {
    my ($provider) = @_;
    my %paths = qesap_get_file_paths();
    return "$paths{deployment_dir}/terraform/" . lc $provider;
}

=head3 qesap_prepare_env

    qesap_prepare_env(variables=>{dict with variables}, provider => 'aws');

    Prepare terraform environment.
    - creates file structures
    - pulls git repository
    - external config files
    - installs pip requirements and OS packages
    - generates config files with qesap script

    For variables example see 'qesap_yaml_replace'
    Returns only result, failure handling has to be done by calling method.
=cut

sub qesap_prepare_env {
    my (%args) = @_;
    my $variables = $args{openqa_variables} ? $args{openqa_variables} : qesap_get_variables();
    my $provider = $args{provider};
    my %paths = qesap_get_file_paths();

    # Option to skip straight to configuration
    unless ($args{only_configure}) {
        qesap_create_folder_tree();
        qesap_get_deployment_code();
        qesap_pip_install();

        record_info("QESAP yaml", "Preparing yaml config file");
        assert_script_run('curl -v -fL ' . $paths{qesap_conf_src} . ' -o ' . $paths{qesap_conf_trgt});
    }

    qesap_yaml_replace(openqa_variables => $variables);
    push(@log_files, $paths{qesap_conf_trgt});

    record_info("QESAP conf", "Generating all terraform and Ansible configuration files");
    push(@log_files, "$paths{terraform_dir}/$provider/terraform.tfvars");
    push(@log_files, "$paths{deployment_dir}/ansible/playbooks/vars/hana_media.yaml");
    my $hana_vars = "$paths{deployment_dir}/ansible/playbooks/vars/hana_vars.yaml";
    my $exec_rc = qesap_execute(cmd => 'configure', verbose => 1);

    if (check_var('PUBLIC_CLOUD_PROVIDER', 'EC2')) {
        my $data = get_credentials('aws.json');
        qesap_create_aws_config();
        qesap_create_aws_credentials($data->{access_key_id}, $data->{secret_access_key});
    }

    push(@log_files, $hana_vars) if (script_run("test -e $hana_vars") == 0);
    qesap_upload_logs(failok => 1);
    die("Qesap deployment returned non zero value during 'configure' phase.") if $exec_rc;
    return;
}

=head3 qesap_ansible_cmd

    Use Ansible to run a command remotely on some or all
    the hosts from the inventory.yaml

    qesap_prepare_env(cmd=>{string}, provider => 'aws');

=over 6

=item B<PROVIDER> - Cloud provider name, used to find the inventory

=item B<CMD> - command to run remotely

=item B<USER> - user on remote host, default to 'cloudadmin'

=item B<FILTER> - filter hosts in the inventory

=item B<FAILOK> - if not set, ansible failure result in die

=item B<HOST_KEYS_CHECK> - if set, add some extra argument to the Ansible call to allow contacting hosts not in the  KnownHost list yet. This enables the use of this api before the call to qesap.py ansible

=back
=cut

sub qesap_ansible_cmd {
    my (%args) = @_;
    croak 'Missing mandatory cmd argument' unless $args{cmd};
    $args{user} ||= 'cloudadmin';
    $args{filter} ||= 'all';

    my $inventory = qesap_get_inventory($args{provider});

    my $ansible_cmd = join(' ',
        'ansible',
        $args{filter},
        '-i', $inventory,
        '-u', $args{user},
        '-b', '--become-user=root',
        '-a', "\"$args{cmd}\"");
    assert_script_run("source " . QESAPDEPLOY_VENV . "/bin/activate");

    $ansible_cmd = $args{host_keys_check} ? join(' ', $ansible_cmd, "-e 'ansible_ssh_common_args=\"-o UpdateHostKeys=yes -o StrictHostKeyChecking=accept-new\"'") : $ansible_cmd;

    $args{failok} ? script_run($ansible_cmd) : assert_script_run($ansible_cmd);

    enter_cmd("deactivate");
}

=head3 qesap_ansible_script_output

    Use Ansible to run a command remotely and get the stdout.
    Command could be executed with elevated privileges

    qesap_ansible_script_output(cmd => 'crm status', provider => 'aws', host => 'vmhana01', root => 1);

    It uses playbook data/sles4sap/script_output.yaml

    1. ansible-playbook run the playbook
    2. the playbook executes the command and redirects the output to file, both remotely
    3. the playbook download the file locally
    4. the file is read and stored to be returned to the caller

    If local_file and local_path are specified, the output is written to file, return is the full path;
    otherwise the return is the command output as string.

=over 8

=item B<PROVIDER> - Cloud provider name, used to find the inventory

=item B<CMD> - command to run remotely

=item B<HOST> - filter hosts in the inventory

=item B<USER> - user on remote host, default to 'cloudadmin'

=item B<ROOT> - 1 to enable remote execution with elevated user, default to 0

=item B<FAILOK> - if not set, ansible failure result in die

=item B<LOCAL_FILE> - filter hosts in the inventory

=item B<LOCAL_PATH> - filter hosts in the inventory

=back
=cut

sub qesap_ansible_script_output {
    my (%args) = @_;
    croak 'Missing mandatory provider argument' unless $args{provider};
    croak 'Missing mandatory cmd argument' unless $args{cmd};
    croak 'Missing mandatory host argument' unless $args{host};
    $args{user} ||= 'cloudadmin';
    $args{root} ||= 0;

    my $inventory = qesap_get_inventory($args{provider});

    my $pb = 'script_output.yaml';
    my $local_path = $args{local_path} // '/tmp/ansible_script_output/';
    my $local_file = $args{local_file} // 'testout.txt';
    my $local_tmp = $local_path . $local_file;
    my $return_string = ((not exists $args{local_path}) && (not exists $args{local_file}));

    if (script_run "test -e $pb") {
        my $cmd = join(' ',
            'curl', '-v', '-fL',
            data_url("sles4sap/$pb"),
            '-o', $pb);
        assert_script_run($cmd);
    }

    my @ansible_cmd = ('ansible-playbook', '-vvvv', $pb);
    push @ansible_cmd, ('-l', $args{host}, '-i', $inventory);
    push @ansible_cmd, ('-u', $args{user});
    push @ansible_cmd, ('-b', '--become-user', 'root') if ($args{root});
    push @ansible_cmd, ('-e', qq("cmd='$args{cmd}'"),
        '-e', "out_path='$local_path'",
        '-e', "out_file='$local_file'");
    push @ansible_cmd, ('-e', "failok=yes") if ($args{failok});

    enter_cmd "rm $local_tmp || echo 'Nothing to delete'" if ($return_string);

    assert_script_run("source " . QESAPDEPLOY_VENV . "/bin/activate");    # venv activate

    $args{failok} ? script_run(join(' ', @ansible_cmd)) : assert_script_run(join(' ', @ansible_cmd));

    enter_cmd("deactivate");    #venv deactivate
    if ($return_string) {
        my $output = script_output("cat $local_tmp");
        enter_cmd "rm $local_tmp || echo 'Nothing to delete'";
        return $output;
    }
    else {
        return $local_tmp;
    }
}

=head3 qesap_create_aws_credentials

    Creates a AWS credentials file as required by QE-SAP Terraform deployment code.
=cut

sub qesap_create_aws_credentials {
    my ($key, $secret) = @_;
    my %paths = qesap_get_file_paths();
    my $credfile = script_output q|awk -F ' ' '/aws_credentials/ {print $2}' | . $paths{qesap_conf_trgt};
    save_tmp_file('credentials', "[default]\naws_access_key_id = $key\naws_secret_access_key = $secret\n");
    assert_script_run 'mkdir -p ~/.aws';
    assert_script_run 'curl ' . autoinst_url . "/files/credentials -o $credfile";
    assert_script_run "cp $credfile ~/.aws/credentials";
}

=head3 qesap_create_aws_config

    Creates a AWS config file in ~/.aws as required by the QE-SAP Terraform & Ansible deployment code.
=cut

sub qesap_create_aws_config {
    my %paths = qesap_get_file_paths();
    my $region = script_output q|awk -F ' ' '/aws_region/ {print $2}' | . $paths{qesap_conf_trgt};
    $region = get_required_var('PUBLIC_CLOUD_REGION') if ($region =~ /^["']?%.+%["']?$/);
    $region =~ s/[\"\']//g;
    save_tmp_file('config', "[default]\nregion = $region\n");
    assert_script_run 'mkdir -p ~/.aws';
    assert_script_run 'curl ' . autoinst_url . "/files/config -o ~/.aws/config";
}

=head3 qesap_remote_hana_public_ips

    Return a list of the public IP addresses of the systems deployed by qesapdeployment, as reported
    by C<terraform output>. Needs to run after C<qesap_execute(cmd => 'terraform');> call.

=cut

sub qesap_remote_hana_public_ips {
    my $prov = get_required_var('PUBLIC_CLOUD_PROVIDER');
    my $tfdir = qesap_get_terraform_dir($prov);
    my $data = decode_json(script_output "terraform -chdir=$tfdir output -json");
    return @{$data->{hana_public_ip}->{value}};
}

=head3 qesap_wait_for_ssh

  Probe specified port on the remote host each 5sec till response.
  Return -1 in case of timeout
  Return total time of retry loop in case of pass.

=over 3

=item B<HOST> - IP of the host to probe

=item B<TIMEOUT> - time to wait before to give up, default is 10mins

=item B<PORT> - port to probe, default is 22

=back
=cut

sub qesap_wait_for_ssh {
    my (%args) = @_;
    croak 'Missing mandatory host argument' unless $args{host};
    $args{timeout} //= bmwqemu::scale_timeout(600);
    $args{port} ||= 22;
    my $start_time = time();
    my $check_port = 1;

    # Looping until reaching timeout or passing two conditions :
    # - SSH port 22 is reachable
    # - journalctl got message about reaching one of certain targets
    while ((my $duration = time() - $start_time) < $args{timeout}) {
        return $duration if (script_run(join(' ', 'nc', '-vz', '-w', '1', $args{host}, $args{port}), quiet => 1) == 0);
        sleep 5;
    }

    return -1;
}

=head3 qesap_cluster_log_cmds

  List of commands to collect logs from a deployed cluster

=cut

sub qesap_cluster_log_cmds {
    my @log_list = (
        {
            Cmd => 'crm status',
            Output => 'crm_status.txt',
        },
        {
            Cmd => 'crm configure show',
            Output => 'crm_configure.txt',
        },
        {
            Cmd => 'lsblk -i -a',
            Output => 'lsblk.txt',
        },
        {
            Cmd => 'journalctl -b --no-pager -o short-precise',
            Output => 'journalctl.txt',
        },
        {
            Cmd => 'systemctl --no-pager --full status sbd',
            Output => 'sbd.txt',
        },
        {
            Cmd => 'lsscsi -i',
            Output => 'lsscsi.txt',
        },
        {
            Cmd => 'cat /var/tmp/hdbinst.log',
            Output => 'hdbinst.log.txt',
        },
        {
            Cmd => 'cat /var/tmp/hdblcm.log',
            Output => 'hdblcm.log.txt',
        },
        {
            Cmd => 'cat /etc/corosync/corosync.conf',
            Output => 'corosync.conf.txt',
        },
        {
            Cmd => 'csync2 -L',
            Output => 'csync2__L.txt',
        },
    );
    if (check_var('PUBLIC_CLOUD_PROVIDER', 'EC2')) {
        push @log_list, {
            Cmd => 'cat ~/.aws/config > aws_config.txt',
            Output => 'aws_config.txt',
        };
    }
    return @log_list;
}

=head3 qesap_cluster_logs

  Collect logs from a deployed cluster

=cut

sub qesap_cluster_logs {
    my $prov = get_required_var('PUBLIC_CLOUD_PROVIDER');
    my $inventory = qesap_get_inventory($prov);
    if (script_run("test -e $inventory") == 0)
    {
        foreach my $host ('vmhana01', 'vmhana02') {
            foreach my $cmd (qesap_cluster_log_cmds()) {
                my $out = qesap_ansible_script_output(cmd => $cmd->{Cmd},
                    provider => $prov,
                    host => $host,
                    failok => 1,
                    root => 1,
                    local_path => '/tmp/',
                    local_file => "$host-$cmd->{Output}");
                upload_logs($out, failok => 1);
            }
        }
    }
}

=head3 qesap_get_vnet

Return the output of az network vnet list
=over 1

=item B<RESOURCE_GROUP> - resource group name to query

=back
=cut

sub qesap_get_vnet {
    my ($resource_group) = @_;
    my $az_cmd = join(' ', 'az', 'network',
        'vnet', 'list',
        '-g', $resource_group,
        '--query', '"[0].name"',
        '-o', 'tsv');
    return script_output($az_cmd, 180);
}

=head3 qesap_get_az_resource_group

Query and return the resource group used
by the qe-sap-deployment

=over 1

=item B<SUBSTRING> - optional substring to be used with aditional grep at the end of the command

=back
=cut

sub qesap_get_az_resource_group {
    my (%args) = @_;
    my $substring = $args{substring} ? " | grep $args{substring}" : "";
    my $job_id = get_current_job_id();
    my $result = script_output("az group list --query \"[].name\" -o tsv | grep $job_id" . $substring);
    record_info('QESAP RG', "result:$result");
    return $result;
}

=head3 qesap_calculate_az_address_range

Calculate the vnet and subnet address
ranges. The format is 10.ip2.ip3.0/21 and
 /24 respectively. ip2 and ip3 are calculated
 using the worker instance number as seed.

=over 1

=item B<SLOT> - integer to be used as seed in calculating addresses

=back

=cut

sub qesap_calculate_az_address_range {
    my %args = @_;
    croak 'Missing mandatory slot argument' unless $args{slot};

    die "Invalid 'slot' argument - valid values are 1-8192" if ($args{slot} > 8192 || $args{slot} < 1);

    my $offset = ($args{slot} - 1) * 8;

    # addresses are of the form 10.ip2.ip3.0/21 and /24 respectively
    #ip2 gets incremented when is >=256
    my $ip2 = int($offset / 256);
    #ip3 gets incremented by 8 until it's >=256, then it resets
    my $ip3 = $offset % 256;

    my $vnet_address_range = sprintf("10.%d.%d.0/21", $ip2, $ip3);
    my $subnet_address_range = sprintf("10.%d.%d.0/24", $ip2, $ip3);

    return (
        vnet_address_range => $vnet_address_range,
        subnet_address_range => $subnet_address_range,
    );
}

=head3 qesap_az_vnet_peering

    Performs peering between the cluster and IBS mirror on Azure.

=over 2

=item B<SOURCE_GROUP> - resource group of source

=item B<TARGET_GROUP> - resource group of target

=back
=cut

sub qesap_az_vnet_peering {
    my (%args) = @_;
    croak 'Missing mandatory source_group argument' unless $args{source_group};
    croak 'Missing mandatory target_group argument' unless $args{target_group};
    $args{source_vnet} = script_output('az network vnet list --resource-group ' . $args{source_group} . ' --query "[0].name" -o tsv');
    $args{target_vnet} = script_output('az network vnet list --resource-group ' . $args{target_group} . ' --query "[0].name" -o tsv');

    my $source_vnet_id = script_output("az network vnet show --resource-group $args{source_group} --name $args{source_vnet} --query id --output tsv");
    record_info("[M] source vnet ID: $source_vnet_id\n");

    my $target_vnet_id = script_output("az network vnet show --resource-group $args{target_group} --name $args{target_vnet} --query id --output tsv");
    record_info("[M] target vnet ID: $target_vnet_id\n");

    my $peering_name = "$args{source_vnet}-$args{target_vnet}";

    assert_script_run("az network vnet peering create --name $peering_name --resource-group $args{source_group} --vnet-name $args{source_vnet} --remote-vnet $target_vnet_id --allow-vnet-access --output table");
    record_info("PEERING SUCCESS (source)", "[M] Peering from $args{source_group}.$args{source_vnet} server was successful\n") if $args{verbose};

    assert_script_run("az network vnet peering create --name $peering_name --resource-group $args{target_group} --vnet-name $args{target_vnet} --remote-vnet $source_vnet_id --allow-vnet-access --output table");
    record_info("PEERING SUCCESS (target)", "[M] Peering from $args{target_group}.$args{target_vnet} server was successful\n") if $args{verbose};

    enter_cmd("echo \"[M] Peering status:\n\"");
    assert_script_run("az network vnet peering show --name $peering_name --resource-group $args{target_group} --vnet-name $args{target_vnet} --output table");
    record_info("PEERING STATUS SUCCESS");
}

=head3 qesap_delete_az_peering

    Performs peering between the cluster and IBS mirror on Azure.

=over 3

=item B<SOURCE_GROUP> - resource group of source

=item B<SOURCE_VNET> - vnet of source

=item B<TARGET_GROUP> - resource group of target

=item B<TARGET_VNET> - vnet of target

=back
=cut

sub qesap_delete_az_peering {
    my (%args) = @_;
    croak 'Missing mandatory source_group argument' unless $args{source_group};
    croak 'Missing mandatory source_vnet argument' unless $args{source_vnet};
    croak 'Missing mandatory target_group argument' unless $args{target_group};
    croak 'Missing mandatory target_vnet argument' unless $args{target_vnet};

    my $peering_name = "$args{source_vnet}-$args{target_vnet}";
    my $source_cmd = "az network vnet peering delete --resource-group $args{source_group} --vnet-name $args{source_vnet} -n $peering_name";
    my $target_cmd = "az network vnet peering delete --resource-group $args{target_group} --vnet-name $args{target_vnet} -n $peering_name";
    assert_script_run($source_cmd);
    assert_script_run($target_cmd);
}

1;

# SUSE's openQA tests
#
# Copyright 2021 SUSE LLC
#
# Copying and distribution of this file, with or without modification,
# are permitted in any medium without royalty provided the copyright
# notice and this notice are preserved. This file is offered as-is,
# without any warranty.

# Summary: The module provides interface to act with Local User page
#
# Maintainer: QE YaST <qa-sle-yast@suse.de>

package Installation::LocalUser::LocalUserPage;
use strict;
use warnings;

sub new {
    my ($class, $args) = @_;
    my $self = bless {
        app => $args->{app}
    }, $class;
    return $self->init();
}

sub init {
    my ($self) = @_;
    $self->{tb_confirm_password} = $self->{app}->textbox({id => 'pw2'});
    $self->{tb_full_name} = $self->{app}->textbox({id => 'full_name'});
    $self->{tb_username} = $self->{app}->textbox({id => 'username'});
    $self->{tb_password} = $self->{app}->textbox({id => 'pw1'});
    $self->{ch_autologin} = $self->{app}->checkbox({id => 'autologin'});
    $self->{ch_use_for_admin} = $self->{app}->checkbox({id => 'root_pw'});
    return $self;
}

sub enter_full_name {
    my ($self, $full_name) = @_;
    return $self->{tb_full_name}->set($full_name);
}

sub enter_username {
    my ($self, $username) = @_;
    return $self->{tb_username}->set($username);
}

sub enter_password {
    my ($self, $password) = @_;
    return $self->{tb_password}->set($password);
}

sub enter_confirm_password {
    my ($self, $password) = @_;
    return $self->{tb_confirm_password}->set($password);
}

sub is_shown {
    my ($self) = @_;
    return $self->{tb_full_name}->exist();
}

sub set_autologin {
    my ($self, $is_checked) = @_;
    $self->{ch_autologin}->check() if $is_checked;
    $self->{ch_autologin}->uncheck() if !$is_checked;
}

sub has_autologin_checked {
    my ($self) = @_;
    $self->{ch_autologin}->is_checked();
}

sub select_use_this_password_for_admin {
    my ($self) = @_;
    return $self->{ch_use_for_admin}->check();
}

sub has_use_same_password_for_admin_checked {
    my ($self) = @_;
    return $self->{ch_use_for_admin}->is_checked();
}

1;

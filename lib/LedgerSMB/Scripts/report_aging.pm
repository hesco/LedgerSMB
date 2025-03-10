
package LedgerSMB::Scripts::report_aging;

=head1 NAME

LedgerSMB::Scripts::report_aging - Aging Reports and Statements for LedgerSMB

=head1 DESCRIPTION

This module provides AR/AP aging reports and statements for LedgerSMB.

=head1 METHODS

=cut

use strict;
use warnings;

use HTTP::Status qw( HTTP_OK HTTP_SEE_OTHER );
use Workflow::Factory qw(FACTORY);

use LedgerSMB::Business_Unit;
use LedgerSMB::Entity;
use LedgerSMB::Entity::Company;
use LedgerSMB::Entity::Contact;
use LedgerSMB::Entity::Credit_Account;
use LedgerSMB::Entity::Location;
use LedgerSMB::Legacy_Util;
use LedgerSMB::Magic qw(CC_EMAIL_TO CC_EMAIL_CC CC_EMAIL_BCC
    CC_BILLING_EMAIL_TO CC_BILLING_EMAIL_CC CC_BILLING_EMAIL_BCC);
use LedgerSMB::Report::Aging;
use LedgerSMB::Scripts::reports;
use LedgerSMB::Template;

our $VERSION = '1.0';

=pod

=over

=item run_report

Runs the report and displays it

=cut

sub run_report{
    my ($request) = @_;

    $request->{business_units} = [];
    for my $count (1 .. ($request->{bc_count} // 0)){
         push @{$request->{business_units}}, $request->{"business_unit_$count"}
               if $request->{"business_unit_$count"};
    }
    return $request->render_report(
        LedgerSMB::Report::Aging->new(%$request)
        );
}


=item generate_statement

This generates a statement and sends it off to the printer, the screen, or
email.

=cut

sub generate_statement {
    my ($request) = @_;

    my $rtype = $request->{report_type}; # in case we need it later
    $request->{report_type} = 'detail'; # needed to generate statement

    my @statements;
    my %filters;
    while ($request->{rowcount} > 0) {
        my $rc = $request->{rowcount};
        --$request->{rowcount};
        next unless $request->{"select_$rc"};

        my ($meta_number, $entity_id, $id) =
            split /:/, $request->{"select_$rc"};
        if (defined $id) {
            $filters{"$meta_number:$entity_id"} //= [];
            push $filters{"$meta_number:$entity_id"}->@*, $id;
        }
        else {
            $filters{"$meta_number:$entity_id"} = 1;
        }
    }

    for my $eca (keys %filters) {
        my ($meta_number, $entity_id) = split /:/, $eca;
        my $company = LedgerSMB::Entity::get($entity_id);
        my $credit_act =
              LedgerSMB::Entity::Credit_Account->get_by_meta_number(
                 $meta_number, $request->{entity_class}
        );
        my ($location) = LedgerSMB::Entity::Location->get_active(
             $request, {entity_id => $entity_id,
                        credit_id => $credit_act->{id},
                       only_class => 1}
        );
        ($location) = LedgerSMB::Entity::Location->get_active(
             $request, {entity_id => $entity_id,
                        credit_id => $credit_act->{id}
                       }
            ) unless defined $location; # select any address if no billing
        my @contact_info = LedgerSMB::Entity::Contact->list(
                 {entity_id => $entity_id, credit_id => $credit_act->{id} }
        );
        $request->{entity_id} = $entity_id;
        my $aging_report = LedgerSMB::Report::Aging->new(
            (ref $filters{$eca}) ? (details_filter => $filters{$eca}) : (),
            %$request);
        $aging_report->run_report($request);
        my $statement = {
              aging => $aging_report,
             entity => $company,
            address => $location,
           contacts => \@contact_info
        };
        push @statements, $statement;
        last if $request->{media} eq 'email';
    }
    $request->{report_type} = $rtype;
    my $template = LedgerSMB::Template->new( # printed document
        path => 'DB',
        dbh  => $request->{dbh},
        locale => $request->{_locale},
        template => $request->{print_template},
        #language => $language->{language_code}, #TODO
        format => uc $request->{print_format},
        method => $request->{media},
    );
    if ($request->{media} eq 'email') {
        my $statement = $statements[0];
        $template->render(
            {
                statements => \@statements,
                DBNAME     => $request->{company},
            });

        my (@to, @cc, @bcc);
        # Select billing or regular addresses from the ECA
        for my $class (CC_BILLING_EMAIL_TO, CC_EMAIL_TO) {
            last if @to;
            @to = grep {
                $_->class_id == $class and $_->credit_id
            } $statement->{contacts}->@*;
        }
        for my $class (CC_BILLING_EMAIL_CC, CC_EMAIL_CC) {
            last if @cc;
            @cc = grep {
                $_->class_id == $class and $_->credit_id
            } $statement->{contacts}->@*;
        }
        for my $class (CC_BILLING_EMAIL_BCC, CC_EMAIL_BCC) {
            last if @bcc;
            @bcc = grep {
                $_->class_id == $class and $_->credit_id
            } $statement->{contacts}->@*;
        }
        # Select billing or regular addresses from the entity
        for my $class (CC_BILLING_EMAIL_TO, CC_EMAIL_TO) {
            last if @to;
            @to = grep {
                $_->class_id == $class and not $_->credit_id
            } $statement->{contacts}->@*;
        }
        for my $class (CC_BILLING_EMAIL_CC, CC_EMAIL_CC) {
            last if @cc;
            @cc = grep {
                $_->class_id == $class and not $_->credit_id
            } $statement->{contacts}->@*;
        }
        for my $class (CC_BILLING_EMAIL_BCC, CC_EMAIL_BCC) {
            last if @bcc;
            @bcc = grep {
                $_->class_id == $class and not $_->credit_id
            } $statement->{contacts}->@*;
        }

        my $wf  = FACTORY()->create_workflow('Email');
        my $ctx = $wf->context;
        $ctx->param( 'from' => $request->setting->get( 'default_email_from' ) );
        $ctx->param( 'to'  => join(', ', map { $_->contact } @to) );
        $ctx->param( 'cc'  => join(', ', map { $_->contact } @cc) );
        $ctx->param( 'bcc' => join(', ', map { $_->contact } @bcc) );

        my $body = $template->{output};
        utf8::encode($body) if utf8::is_utf8($body);  ## no critic
        my $att = {
            content   => $body,
            mime_type => $template->{mimetype},
            file_name => 'aging-report.' . lc($request->{print_format}),
        };
        $ctx->param( attachment => $att );
        $wf->execute_action( 'Attach' );

        return [ HTTP_SEE_OTHER,
                 [ Location =>
                   'email.pl?id=' . $wf->id
                   . '&action=render&callback=reports.pl%3F'
                   . 'report_name%3Daging'
                   . '%26module_name%3Dgl'
                   . '%26action%3Dstart_report'
                   . '%26entity_class%3D' . $request->{entity_class} ],
                 [ '' ] ];
    } elsif ($request->{media} eq 'screen'){
        $template->render(
            {
                statements => \@statements,
                DBNAME     => $request->{company},
            });
        my $body = $template->{output};
        utf8::encode($body) if utf8::is_utf8($body);  ## no critic
        my $filename = 'aging-report.' . lc($request->{print_format});
        return
            [ HTTP_OK,
              [
               'Content-Type' => $template->{mimetype},
               'Content-Disposition' => qq{attachment; filename="$filename"},
              ],
              [ $body ] ];
    } else {
        $template->render({ statements => \@statements });
        LedgerSMB::Legacy_Util::output_template($template, $request);
        $request->{module_name}='gl';
        $request->{report_name}='aging';
        return LedgerSMB::Scripts::reports::start_report($request);
    }
    # Unreachable
}

=back

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2012 The LedgerSMB Core Team

This file is licensed under the GNU General Public License version 2, or at your
option any later version.  A copy of the license should have been included with
your software.

=cut

1;

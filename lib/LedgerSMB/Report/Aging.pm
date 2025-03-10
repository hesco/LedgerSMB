
package LedgerSMB::Report::Aging;

=head1 NAME

LedgerSMB::Report::Aging - AR/AP Aging reports for LedgerSMB

=head1 SYNPOSIS

  my $agereport = LedgerSMB::Report::Aging->new(%$request);
  $agereport->run;
  $agereport->render($request, $format);

=head1 DESCRIPTION

This module provides reports that show how far overdue payments for invoices
are.  This can be useful to help better manage collection of moneys owed, etc.

This module is also capable of printing statements, which are basically aging
reportins aimed at the customer in question.

=cut

use Moose;
use namespace::autoclean;
extends 'LedgerSMB::Report';

use LedgerSMB::Business_Unit_Class;
use LedgerSMB::Business_Unit;

use List::Util qw(none);

=head1 PROPERTIES

=over

=item columns

Read-only accessor, returns a list of columns.

=over

=item select

=item credit_account

=item language

=item invnumber

=item order

=item transdate

=item duedate

=item c0

=item c30

=item c60

=item c90

=item total

=item one for each business unit class returned

=back

=cut




sub columns {
    my ($self) = @_;
    our @COLUMNS = ();
    my $credit_label;
    my $base_href;
    if ($self->entity_class == 1) {
        $credit_label = $self->Text('Vendor');
        $base_href = 'ap.pl?action=edit&id='; # for details
    } elsif ($self->entity_class == 2){
        $credit_label = $self->Text('Customer');
        $base_href = 'ar.pl?action=edit&id='; # for details
    }
    push @COLUMNS,
      {col_id => 'select',
         type => 'checkbox',
         name => 'X',
       toggle => 1,
      },

      {col_id => 'name',
         name => $credit_label,
         type => 'text',
       pwidth => 1, },

      {col_id => 'language',
         name => $self->Text('Language'),
         type => 'select',
       pwidth => '0', };

   if ($self->report_type eq 'detail'){
     push @COLUMNS,
          {col_id => 'invnumber',
             name => $self->Text('Invoice'),
             type => 'href',
        href_base => $base_href,
           pwidth => '3', },

          {col_id => 'ordnumber',
             name => $self->Text('Description'),
             type => 'text',
           pwidth => '6', },

          {col_id => 'transdate',
             name => $self->Text('Date'),
             type => 'text',
           pwidth => '1', },

          {col_id => 'duedate',
             name => $self->Text('Due Date'),
             type => 'text',
           pwidth => '2', };
    }

    push @COLUMNS,
    {col_id => 'c0',
       name => $self->Text('Current'),
       type => 'text',
      money => 1,
     pwidth => '2', },

    {col_id => 'c30',
       name => '30',
       type => 'text',
      money => 1,
     pwidth => '3', },

    {col_id => 'c60',
       name => '60',
       type => 'text',
      money => 1,
     pwidth => '3', },

    {col_id => 'c90',
       name => '90',
       type => 'text',
      money => 1,
     pwidth => '3', },

    {col_id => 'total',
       name => $self->Text('Total'),
       type => 'text',
      money => 1,
     pwidth => '1', };
    return \@COLUMNS;
}

    # TODO:  business_units int[]

=item filter_template

Returns the template name for the filter.

=cut

sub filter_template {
    return 'journal/search';
}

=item name

Returns the localized template name

=cut

sub name {
    my ($self) = @_;
    return $self->Text('Aging Report');
}

=item template

Returns the name of the template to use

=cut

sub template {
    my ($self) = @_;
    if (not $self->format or (uc($self->format) eq 'HTML')
           or (uc($self->format) eq 'PDF'))
    {
           return 'aging_report';
    }
    else {
       return undef;
    }
}

=back

=head2 Criteria Properties

Note that in all cases, undef matches everything.

=over

=item report_type

Is 'summary' or 'detail'

=cut

has 'report_type' => (is => 'rw', isa => 'Str');

=item accno

Exact match for the account number for the AR/AP account

=cut

has 'accno'  => (is => 'rw', isa => 'Maybe[Str]');


=item to_date

Calculate report as on a specific date

=cut

has 'to_date'=> (is => 'rw', coerce => 1, isa => 'LedgerSMB::Moose::Date');

=item entity_class

1 for vendor, 2 for customer

=cut

has 'entity_class' => (is => 'ro', isa => 'Maybe[Int]');

=item entity_id

Customer/Vendor entity id

=cut

has entity_id => (is => 'ro', isa => 'Maybe[Int]');
has name_part => (is => 'ro', isa => 'Maybe[Str]');

=item details_filter

=cut

has details_filter => (is => 'ro', isa => 'Maybe[ArrayRef]',
                       predicate => 'has_details_filter');



has c0total => (is => 'rw', init_arg => undef);
has c30total => (is => 'rw', init_arg => undef);
has c60total => (is => 'rw', init_arg => undef);
has c90total => (is => 'rw', init_arg => undef);
has total => (is => 'rw', init_arg => undef);

=back

=head1 METHODS

=over

=item run_report()

Runs the report, and assigns rows to $self->rows.

=cut

sub run_report{
    my ($self,$request) = @_;
    my @rows = $self->call_dbmethod(funcname => 'report__invoice_aging_' .
                                                $self->report_type);
    my @result;
    for my $row (@rows) {
        next if ($self->has_details_filter
                 and none { $_ == $row->{id} } $self->details_filter->@*);
        push @result, $row;

        if ($self->report_type eq 'detail') {
            $row->{row_id} =
                "$row->{account_number}:$row->{entity_id}:$row->{id}";
        } else {
            $row->{row_id} = "$row->{account_number}:$row->{entity_id}";
        }
        $self->c0total($self->c0total + $row->{c0});
        $self->c30total($self->c30total + $row->{c30});
        $self->c60total($self->c60total + $row->{c60});
        $self->c90total($self->c90total + $row->{c90});
        $row->{total} = $row->{c0} + $row->{c30} + $row->{c60} + $row->{c90};
        $self->total($self->total + $row->{total});
    }
    return $self->rows(\@result);
}

=back

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2012 The LedgerSMB Core Team

This file is licensed under the GNU General Public License version 2, or at your
option any later version.  A copy of the license should have been included with
your software.

=cut

__PACKAGE__->meta->make_immutable;

1;

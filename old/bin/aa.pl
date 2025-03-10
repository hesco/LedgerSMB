#=====================================================================
# LedgerSMB Small Medium Business Accounting
# http://www.ledgersmb.org/
#
# Copyright (C) 2006
# This work contains copyrighted information from a number of sources all used
# with permission.
#
# This file contains source code included with or based on SQL-Ledger which
# is Copyright Dieter Simader and DWS Systems Inc. 2000-2005 and licensed
# under the GNU General Public License version 2 or, at your option, any later
# version.  For a full list including contact information of contributors,
# maintainers, and copyright holders, see the CONTRIBUTORS file.
#
# Original Copyright Notice from SQL-Ledger 2.6.17 (before the fork):
# Copyright (c) 2005
#
#  Author: DWS Systems Inc.
#     Web: http://www.sql-ledger.org
#
#  Contributors:
#
#
#  Author: DWS Systems Inc.
#     Web: http://www.ledgersmb.org/
#
#  Contributors:
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
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
#======================================================================
#
# AR / AP
#
#======================================================================

package lsmb_legacy;
use LedgerSMB::Form;
use LedgerSMB::IR;
use LedgerSMB::IS;
use LedgerSMB::Setting;
use LedgerSMB::Tax;
use LedgerSMB::DBObject::Draft;
use LedgerSMB::DBObject::TransTemplate;

# any custom scripts for this one
if ( -f "old/bin/custom/aa.pl" ) {
    eval { require "old/bin/custom/aa.pl"; };
}

my $is_update;


# end of main

# this is for our long dates
# $locale->text('January')
# $locale->text('February')
# $locale->text('March')
# $locale->text('April')
# $locale->text('May')
# $locale->text('June')
# $locale->text('July')
# $locale->text('August')
# $locale->text('September')
# $locale->text('October')
# $locale->text('November')
# $locale->text('December')

# this is for our short month
# $locale->text('Jan')
# $locale->text('Feb')
# $locale->text('Mar')
# $locale->text('Apr')
# $locale->text('May')
# $locale->text('Jun')
# $locale->text('Jul')
# $locale->text('Aug')
# $locale->text('Sep')
# $locale->text('Oct')
# $locale->text('Nov')
# $locale->text('Dec')

sub copy_to_new{
    delete $form->{id};
    delete $form->{invnumber};
    delete $form->{approved};
    $form->{paidaccounts} = 1;
    if ($form->{paid_1}){
        delete $form->{paid_1};
    }
    update();
}

sub new_screen {
    my @reqprops = qw(ARAP vc dbh stylesheet batch_id script _locale);
    $oldform = $form;
    $form = {};
    bless $form, 'Form';
    for (@reqprops){
        $form->{$_} = $oldform->{$_};
    }
    &add();
}

sub add {
    $form->{title} = "Add";

    $form->{callback} = "$form->{script}?action=add"
      unless $form->{callback};
    if (defined $form->{type}
        and $form->{type} eq "credit_note"){
        $form->{reverse} = 1;
        $form->{subtype} = 'credit_note';
        $form->{type} = 'transaction';
    } elsif (defined $form->{type}
             and $form->{type} eq 'debit_note'){
        $form->{reverse} = 1;
        $form->{subtype} = 'debit_note';
        $form->{type} = 'transaction';
    }
    else {
        $form->{reverse} = 0;
    }

    &create_links;

    $form->{focus} = "amount_1";
    &display_form;
    return 1;
}

sub edit {

    &create_links;
    $form->{title} = $locale->text("Edit");
    if ($form->{reverse}){
        if ($form->{ARAP} eq 'AR'){
            $form->{subtype} = 'credit_note';
            $form->{type} = 'transaction';
        } elsif ($form->{ARAP} eq 'AP'){
            $form->{subtype} = 'debit_note';
            $form->{type} = 'transaction';
        } else {
            $form->error("Unknown AR/AP selection value: $form->{ARAP}");
        }

    }

    &display_form;
}

sub display_form {
    my $invnumber = "sinumber";
    if ( $form->{vc} eq 'vendor' ) {
        $invnumber = "vinumber";
    }
    $form->{sequence_select} = $form->sequence_dropdown($invnumber)
        unless $form->{id} and ($form->{vc} eq 'vendor');
    $form->{format} = $form->get_setting('format') unless $form->{format};
    $form->close_form;
    $form->generate_selects(\%myconfig);
    $form->open_form;
    AA->get_files($form, $locale);
    &form_header;
    &form_footer;

}

sub create_links {

    if ( $form->{script} eq 'ap.pl' ) {
        $form->{ARAP} = 'AP';
        $form->{vc}   = 'vendor';
    }
    elsif ( $form->{script} eq 'ar.pl' ) {
        $form->{ARAP} = 'AR';
        $form->{vc}   = 'customer';
    }

     $form->create_links( module => $form->{ARAP},
                                 myconfig => \%myconfig,
                                 vc => $form->{vc},
                                 billing => ($form->{vc}//'') eq 'customer'
                                      && ($form->{type}//'') eq 'invoice')
        unless $form->{"$form->{ARAP}_links"};


    $duedate     = $form->{duedate};
    $crdate     = $form->{crdate};

    $form->{formname} = "transaction";
    $form->{media}    //= $myconfig{printer};

    # currencies
    if (!$form->{currencies}){
        $form->error($locale->text(
           'No currencies defined.  Please set these up under System/Defaults.'
        ));
    }
    @curr = @{$form->{currencies}};

    for (@curr) {
        $form->{selectcurrency} .= "<option value=\"$_\">$_</option>\n"
    }

    my $vc = $form->{vc};
    AA->get_name( \%myconfig, \%$form )
            unless ($form->{"old$vc"} and $form->{$vc} and $form->{"old$vc"} eq $form->{$vc})
                    or ($form->{"old$vc"} and $form->{"old$vc"} =~ /^\Q$form->{$vc}\E--/);

    $form->{currency} =~ s/ //g if $form->{currency};
    $form->{duedate}     = $duedate     if $duedate;
    $form->{crdate}      = $crdate      if $crdate;

    if ($form->{"$form->{vc}"} && $form->{"$form->{vc}"} !~ /--/){
        $form->{"old$form->{vc}"} = $form->{$form->{vc}} . '--' . $form->{"$form->{vc}_id"};
    } else {
        $form->{"old$form->{vc}"} = $form->{$form->{vc}};
    }
    $form->{oldtransdate} = $form->{transdate};

    # Business Reporting Units
    $form->all_business_units;

    # forex
    $form->{forex} = $form->{exchangerate};
    $exchangerate = ( $form->{exchangerate} ) ? $form->{exchangerate} : 1;

    $netamount = 0;
    $tax       = 0;
    $taxrate   = 0;
    $ml = LedgerSMB::PGNumber->new(
        ($form->{ARAP} eq 'AR') ? 1 : -1
    );

    foreach my $key ( keys %{ $form->{"$form->{ARAP}_links"} } ) {


        # if there is a value we have an old entry
        if ($form->{acc_trans}{$key}) {
        foreach my $i ( 1 .. scalar @{ $form->{acc_trans}{$key} } ) {


            if ( $key eq "$form->{ARAP}_paid" ) {

                $form->{"$form->{ARAP}_paid_$i"} =
"$form->{acc_trans}{$key}->[$i-1]->{accno}--$form->{acc_trans}{$key}->[$i-1]->{description}";
                $form->{"paid_$i"} =
                  $form->{acc_trans}{$key}->[ $i - 1 ]->{amount} * -1 * $ml;
                $form->{"datepaid_$i"} =
                  $form->{acc_trans}{$key}->[ $i - 1 ]->{transdate};
                $form->{"source_$i"} =
                  $form->{acc_trans}{$key}->[ $i - 1 ]->{source};
                $form->{"memo_$i"} =
                  $form->{acc_trans}{$key}->[ $i - 1 ]->{memo};

                $form->{"forex_$i"} = $form->{"exchangerate_$i"} =
                  $form->{acc_trans}{$key}->[ $i - 1 ]->{exchangerate};

                $form->{paidaccounts}++;
            }
            else {

                $akey = $key;
                $akey =~ s/$form->{ARAP}_//;

                if ( $key eq "$form->{ARAP}_tax" ) {
                    $form->{"${key}_$form->{acc_trans}{$key}->[$i-1]->{accno}"}
                      = "$form->{acc_trans}{$key}->[$i-1]->{accno}--$form->{acc_trans}{$key}->[$i-1]->{description}";
                    $form->{"${akey}_$form->{acc_trans}{$key}->[$i-1]->{accno}"}
                      = $form->{acc_trans}{$key}->[ $i - 1 ]->{amount} * $ml;

                    $tax +=
                      $form->{
                        "${akey}_$form->{acc_trans}{$key}->[$i-1]->{accno}"};
                    $taxrate +=
                      $form->{"$form->{acc_trans}{$key}->[$i-1]->{accno}_rate"};

                }
                else {


                    $form->{"${akey}_$i"} =
                      $form->{acc_trans}{$key}->[ $i - 1 ]->{amount} * $ml;

                    if ( $akey eq 'amount' ) {
                        $form->{"description_$i"} =
                          $form->{acc_trans}{$key}->[ $i - 1 ]->{memo};

             $form->{"entry_id_$i"} =
                          $form->{acc_trans}{$key}->[ $i - 1 ]->{entry_id};

            $form->{"taxformcheck_$i"}=1 if(AA->get_taxcheck($form->{"entry_id_$i"},$form->{dbh}));

                       $form->{rowcount}++;
                        $netamount += $form->{"${akey}_$i"};

                        my $ref = $form->{acc_trans}{$key}->[ $i - 1 ];
                        for my $cls (@{$form->{bu_class}}){
                           if ($ref->{"b_unit_$cls->{id}"}){
                              $form->{"b_unit_$cls->{id}_$i"}
                                                         = $ref->{"b_unit_$cls->{id}"};
                           }
                        }
                    }
                    elsif (not $form->{acc_trans}{$key}->[$i-1]
                           ->{payment_line}) {
                        $form->{invtotal} =
                          $form->{acc_trans}{$key}->[ $i - 1 ]->{amount} * -1 * $ml;
                    }
                    $form->{"${key}_$i"} =
"$form->{acc_trans}{$key}->[$i-1]->{accno}--$form->{acc_trans}{$key}->[$i-1]->{description}";



                }
            }
        }
        }
    }

    $form->{paidaccounts} = 1 if not $form->{paidaccounts};


    # check if calculated is equal to stored
    # taxincluded can't be calculated
    # this works only if all taxes are checked

    if ( !$form->{oldinvtotal} ) { # first round loading (or amount was 0)
        for (@taxaccounts) { $form->{ "calctax_" . $_->{account} } = 1 }
    }

    $form->{rowcount}++ if ( $form->{id} || !$form->{rowcount} );
    $form->{rowcount} = 1 unless $form->{"$form->{ARAP}_amount_1"};

    # readonly
    if ( !$form->{readonly} ) {
        $form->{readonly} = 1
          if $myconfig{acs} && $myconfig{acs} =~ /$form->{ARAP}--Add Transaction/;
    }
    delete $form->{selectcurrency};
    #$form->generate_selects(\%myconfig);
    $form->{$form->{ARAP}} = $form->{"$form->{ARAP}_1"} unless $form->{$form->{ARAP}} and $form->{action} eq 'update';

}

sub form_header {
     my $min_lines = $form->get_setting('min_empty') // 0;

     $form->generate_selects(\%myconfig) unless $form->{"select$form->{ARAP}"};
    $title = $form->{title};
    $form->all_business_units($form->{transdate},
                              $form->{"$form->{vc}_id"},
                              $form->{ARAP});

    if($form->{batch_id})
    {
        $form->{batch_control_code}=$form->get_batch_control_code($form->{dbh},$form->{batch_id});
        $form->{batch_description}=$form->get_batch_description($form->{dbh},$form->{batch_id});
    }
    #     $locale->text('Add AR Transaction');
    #     $locale->text('Add AP Transaction');
    #   $locale->text('Edit AR Transaction');
    #   $locale->text('Edit AP Transaction');
    if ($form->{ARAP} eq 'AP'){
        $eclass = '1';
    } elsif ($form->{ARAP} eq 'AR'){
        $eclass = '2';
    }
    my $title_msgid="$title $form->{ARAP} Transaction";
    my $status_div_id = $form->{ARAP} . '-transaction'
         . ($form->{reverse} ? '-reverse' : '');
    if ($form->{reverse} == 0){
       #$form->{title} = $locale->text("[_1] [_2] Transaction", $title, $form->{ARAP});
       $form->{title} = $locale->maketext($title_msgid);
    }
    elsif($form->{reverse} == 1) {
       if ($form->{subtype} eq 'credit_note'){
           $title_msgid="$title Credit Note";
           $form->{title}=$locale->maketext($title_msgid);
           #$form->{title} = $locale->text("[_1] Credit Note", $title);
       } elsif ($form->{subtype} eq 'debit_note'){
           $title_msgid="$title Debit Note";
           $form->{title}=$locale->maketext($title_msgid);
           #$form->{title} = $locale->text("[_1] Debit Note", $title);
       } else {
           $form->error("Unknown subtype $form->{subtype} in $form->{ARAP} "
              . "transaction.");
       }
    }
    else {
       $form->error('Reverse flag not true or false on AR/AP transaction');
    }

    $form->{taxincluded} = ( $form->{taxincluded} ) ? "checked" : "";

    # $locale->text('Add Debit Note')
    # $locale->text('Edit Debit Note')
    # $locale->text('Add Credit Note')
    # $locale->text('Edit Credit Note')
    # $locale->text('Add AP Transaction')
    # $locale->text('Edit AP Transaction')

    $form->{selectprojectnumber} =
      $form->unescape( $form->{selectprojectnumber} );

    # format amounts
    my $formatted_exchangerate =
      $form->format_amount( \%myconfig, $form->{exchangerate} );

    $exchangerate = qq|<tr>|;
    $exchangerate .= qq|
                <th align=right nowrap><label for="currency">| . $locale->text('Currency') . qq|</label></th>
        <td><select data-dojo-type="dijit/form/Select" id=currency name=currency>$form->{selectcurrency}</select></td> |
      if $form->{defaultcurrency};
    if (   $form->{defaultcurrency}
        && $form->{currency} ne $form->{defaultcurrency} )
    {
            $exchangerate .= qq|
        <th align=right><label for="exchangerate">| . $locale->text('Exchange Rate') . qq|</label></th>
        <td><input data-dojo-type="dijit/form/TextBox" name=exchangerate id=exchangerate size=10 value=$formatted_exchangerate></td>
|;
    }
     else {
         $exchangerate .= q|<input name=exchangerate type=hidden value=1>|;
    }
    $exchangerate .= qq|
</tr>
|;

    if ( ( $rows = $form->numtextrows( $form->{notes}, 50 ) - 1 ) < 2 ) {
        $rows = 2;
    }
    $form->{notes} //= '';
    $notes =
qq|<textarea data-dojo-type="dijit/form/Textarea" name=notes rows=$rows cols=50 wrap=soft>$form->{notes}</textarea>|;
    $form->{intnotes} //= '';
    $intnotes =
qq|<textarea data-dojo-type="dijit/form/Textarea" name=intnotes rows=$rows cols=35 wrap=soft>$form->{intnotes}</textarea>|;

    $department = qq|
          <tr>
        <th align="right" nowrap>| . $locale->text('Department') . qq|</th>
        <td colspan=3><select data-dojo-type="dijit/form/Select" id=department name=department>$form->{selectdepartment}</select>
        <input type=hidden name=selectdepartment value="|
      . $form->escape( $form->{selectdepartment}, 1 ) . qq|">
        </td>
          </tr>
        | if $form->{selectdepartment};
     $department //= '';

    $n = ( ($form->{creditremaining} // 0) < 0 ) ? "0" : "1";

    $name =
      ( $form->{"select$form->{vc}"} )
      ? qq|<select data-dojo-type="lsmb/FilteringSelect" id="$form->{vc}" name="$form->{vc}"><option></option>$form->{"select$form->{vc}"}</select>|
      : qq|<input data-dojo-type="dijit/form/TextBox" id="$form->{vc}" name="$form->{vc}" value="$form->{$form->{vc}}" size=35>
                 <a href="erp.pl?action=root#contact.pl?action=add&entity_class=$eclass"
                    id="new-contact" target="_blank">[|
                 .  $locale->text('New') . qq|]</a>|;

    $employee = qq|
                <input type=hidden name=employee value="$form->{employee}">
|;

    if ( $form->{selectemployee} ) {
        $label =
          ( $form->{ARAP} eq 'AR' )
          ? $locale->text('Salesperson')
          : $locale->text('Employee');

        $employee = qq|
          <tr>
        <th align=right nowrap><label for="employee">$label</label></th>
        <td><select data-dojo-type="dijit/form/Select" id=employee name=employee>$form->{selectemployee}</select></td>
        <input type=hidden name=selectemployee value="|
          . $form->escape( $form->{selectemployee}, 1 ) . qq|">
          </tr>
|;
    }

    $focus = ( $form->{focus} ) ? $form->{focus} : "amount_$form->{rowcount}";

    $form->header;

 print qq|
<body> | .
$form->open_status_div($status_div_id) . qq|
<form method="post" data-dojo-type="lsmb/Form" action=$form->{script}>
<input type=hidden name=type value="$form->{formname}">
<input type=hidden name=title value="$title">

|;
    if (!defined $form->{approved}){
        $form->{approved} = 1;
    }
    $form->hide_form(
        qw(batch_id approved id printed emailed sort
           oldtransdate audittrail recurring checktax reverse subtype
           entity_control_code tax_id meta_number default_reportable
           address city zipcode state country)
    );

    if ( $form->{vc} eq 'customer' ) {
        $label = $locale->text('Customer');
    }
    else {
        $label = $locale->text('Vendor');
    }

    $form->hide_form(
        "old$form->{vc}",  "$form->{vc}_id",
        "terms",           "creditlimit",
        "creditremaining", "defaultcurrency",
        "rowcount"
    );

    print qq|

<table width=100%>
  <tr class=listtop>
    <th class=listtop>$form->{title}</th>
  </tr>
  <tr height="5"></tr>
  <tr valign=top>
    <td>
      <table width=100% id="invoice-header">
        <tr valign=top>
      <td>
        <table>
          <tr>
        <th align="right" nowrap><label for="$form->{vc}">$label</label></th>
        <td colspan=3>$name
                </td>
          </tr>
          <tr>
        <td colspan=3>
          <table width=100%>
            <tr> |;
    if (LedgerSMB::Setting->new(%$form)->get('show_creditlimit')){
       print qq|
              <th align=left nowrap>| . $locale->text('Credit Limit') . qq|</th>
              <td>$form->{creditlimit}</td>
              <th align=left nowrap>| . $locale->text('Remaining') . qq|</th>
              <td class="plus$n">|
      . $form->format_amount( \%myconfig, $form->{creditremaining}, 0, "0" )
      . qq|</td>|;
    } else {
       print qq|<td>&nbsp;</td>|;
    }
    print qq|
            </tr>
          </table>
        </td>
          </tr>
|;
        if($form->{batch_id})
        {
        print qq|    <tr>
        <th align="right" nowrap>| .
            $locale->text('Batch Control Code') . qq|</th>
        <td>$form->{batch_control_code}</td>
          </tr>
        <tr>
        <th align="right" nowrap>| .
            $locale->text('Batch Name') . qq|</th>
        <td>$form->{batch_description}</td>
          </tr>

|;

        }



        if ($form->{entity_control_code}) {
            $form->{$_} //= '' for (qw/entity_control_code tax_id
                                    meta_number address city/);
            print qq|
            <tr>
        <th align="right" nowrap>| .
            $locale->text('Entity Control Code') . qq|</th>
        <td colspan=3><a href="erp.pl?action=root#contact.pl?action=get_by_cc&control_code=$form->{entity_control_code}" target="_blank"><b>$form->{entity_control_code}</b></a></td>
          </tr>
            <tr>
        <th align="right" nowrap>| .
            $locale->text('Tax ID') . qq|</th>
        <td colspan=3>$form->{tax_id}</td>
          </tr>
            <tr>
        <th align="right" nowrap>| .
            $locale->text('Account') . qq|</th>
        <td colspan=3>$form->{meta_number}</td>
          </tr>
              <tr class="address_row">
                <th align="right" nowrap>| .
                        $locale->text('Address'). qq|</th>
                <td colspan=3>$form->{address}, $form->{city}</td>
              </tr>
        |;
           }

     $form->{$_} //= '' for (qw(description invnumber ordnumber crdate transdate duedate
                             ponumber));
     $myconfig{dateformat} //= '';
     $employee //= '';
     $form->{sequence_select} //= '';
     print qq|
          $exchangerate
          $department
            <tr>
               <th align="right" nowrap><label for="description">| . $locale->text('Description') . qq|</label>
               </th>
               <td><input data-dojo-type="dijit/form/TextBox" type="text" name="description" id="description" size="40"
                   value="| . ($form->{description} // '') . qq|" /></td>
            </tr>
        </table>
      </td>
      <td align=right>
        <table>
          $employee
          <tr>
        <th align=right nowrap><label for="invnum">| . $locale->text('Invoice Number') . qq|</label></th>
        <td><input data-dojo-type="dijit/form/TextBox" name=invnumber id=invnum size=20 value="$form->{invnumber}">
                      $form->{sequence_select}</td>
          </tr>
          <tr>
        <th align=right nowrap><label for="ordnum">| . $locale->text('Order Number') . qq|</label></th>
        <td><input data-dojo-type="dijit/form/TextBox" name=ordnumber id=ordnum size=20 value="$form->{ordnumber}"></td>
          </tr>
              <tr>
                <th align=right nowrap><label for="crdate">| . $locale->text('Invoice Created') . qq|</label></th>
                <td><input class="date" data-dojo-type="lsmb/DateTextBox" name=crdate id=crdate size=11 title="($myconfig{'dateformat'})" value="$form->{crdate}" data-dojo-props="defaultIsToday:true"></td>
              </tr>
          <tr>
        <th align=right nowrap><label for="transdate">| . $locale->text('Invoice Date') . qq|</label></th>
        <td><input class="date" data-dojo-type="lsmb/DateTextBox" name=transdate id=transdate size=11 title="($myconfig{'dateformat'})" value="$form->{transdate}" data-dojo-props="defaultIsToday:true"></td>
          </tr>
          <tr>
        <th align=right nowrap><label for="duedate">| . $locale->text('Due Date') . qq|</label></th>
        <td><input class="date" data-dojo-type="lsmb/DateTextBox" name=duedate id=duedate size=11 title="$myconfig{'dateformat'}" value=$form->{duedate}></td>
          </tr>
          <tr>
        <th align=right nowrap><label for="ponum">| . $locale->text('PO Number') . qq|</label></th>
        <td><input data-dojo-type="dijit/form/TextBox" name=ponumber id=ponum size=20 value="$form->{ponumber}"></td>
          </tr>
        </table>
      </td>
    </tr>
      </table>
    </td>
  </tr>
  <tr>
    <td>
      <table id="transaction-lines">
|;

    print qq|
    <thead>
    <tr class="listheading">
      <th>| . $locale->text('Amount') . qq|</th>
     <th>| . (($form->{currency} ne $form->{defaultcurrency}) ? $form->{defaultcurrency} : '') . qq|</th>
      <th>| . $locale->text('Account') . qq|</th>
      <th>| . $locale->text('Description') . qq|</th>
      <th>| . $locale->text('Tax Form Applied') . qq|</th>|;
    for my $cls (@{$form->{bu_class}}){
        if (scalar @{$form->{b_units}->{"$cls->{id}"}}){
            print qq|<th>| . $locale->maketext($cls->{label}) . qq|</th>|;
        }
    }
    print qq|
    </th>
    </thead>
|;


    # Display rows

    foreach my $i ( 1 .. $form->{rowcount} + $min_lines) {

        # format amounts
        $form->{"amount_$i"} =
          $form->format_amount( \%myconfig,$form->{"amount_$i"}, LedgerSMB::Setting->new(%$form)->get('decimal_places') );

        $project = qq|
      <td align=right><select data-dojo-type="dijit/form/Select" id="projectnumber_$i" name="projectnumber_$i">$form->{"selectprojectnumber_$i"}</select></td>
            | if $form->{selectprojectnumber};
        $project //= '';

        $form->{"description_$i"} //= '';
        if ( ( $rows = $form->numtextrows( $form->{"description_$i"}, 40 ) ) >
            1 )
        {
            $description =
qq|<td><textarea data-dojo-type="dijit/form/Textarea" name="description_$i" rows=$rows cols=40>$form->{"description_$i"}</textarea></td>|;
        }
        else {
            $description =
qq|<td><input data-dojo-type="dijit/form/TextBox" name="description_$i" size=40 value="$form->{"description_$i"}"></td>|;
        }

    $taxchecked="";
    if($form->{"taxformcheck_$i"} or ($form->{default_reportable} and ($i == $form->{rowcount})))
    {
        $taxchecked=qq|CHECKED="CHECKED"|;

    }

    $taxformcheck=qq|<td><input type="checkbox" data-dojo-type="dijit/form/CheckBox" name="taxformcheck_$i" value="1" $taxchecked></td>|;
        print qq|
    <tr valign=top class="transaction-line $form->{ARAP}" id="line-$i">
     <td><input data-dojo-type="dijit/form/TextBox" name="amount_$i" size=10 value="$form->{"amount_$i"}"></td>
     <td>| . (($form->{currency} ne $form->{defaultcurrency})
              ? $form->format_amount(\%myconfig, $form->parse_amount( \%myconfig, $form->{"amount_$i"} )
                                                  * $form->{exchangerate}, LedgerSMB::Setting->new(%$form)->get('decimal_places'))
              : '')  . qq|</td>
     <td><select data-dojo-type="lsmb/FilteringSelect" id="$form->{ARAP}_amount_$i" name="$form->{ARAP}_amount_$i"><option></option>$form->{"select$form->{ARAP}_amount_$i"}</select></td>
      $description
          $taxformcheck
      $project|;

        for my $cls (@{$form->{bu_class}}){
            if (scalar @{$form->{b_units}->{"$cls->{id}"}}){
                print qq|<td><select data-dojo-type="dijit/form/Select" id="b_unit_$cls->{id}_$i" name="b_unit_$cls->{id}_$i">
                                    <option>&nbsp;</option>|;
                      for my $bu (@{$form->{b_units}->{"$cls->{id}"}}){
                         my $selected = '';
                         if ($form->{"b_unit_$cls->{id}_$i"} eq $bu->{id}){
                            $selected = 'selected="selected"';
                         }
                         print qq|  <option value="$bu->{id}" $selected>
                                        $bu->{control_code}
                                    </option>|;
                      }
                print qq|
                             </select>
                        </th>|;
            }
        }
        print qq|
    </tr>
|;

    $form->hide_form( "entry_id_$i"); #New block of code to pass entry_id

    }
     my $tax_base = $form->{invtotal};
    foreach my $item ( split / /, $form->{taxaccounts} ) {
        $form->{"calctax_$item"} =
          ( $form->{"calctax_$item"} ) ? "checked" : "";
        $form->{"tax_$item"} =
          $form->format_amount( \%myconfig, $form->{"tax_$item"}, LedgerSMB::Setting->new(%$form)->get('decimal_places') );
        print qq|
        <tr class="transaction-row $form->{ARAP} tax" id="taxrow_$item">
      <td><input data-dojo-type="dijit/form/TextBox" name="tax_$item" id="tax_$item"
                     size=10 value=$form->{"tax_$item"} /></td>
      <td align=right><input id="calctax_$item" name="calctax_$item"
                                 class="checkbox" type="checkbox" data-dojo-type="dijit/form/CheckBox" value=1
                                 $form->{"calctax_$item"}
                            title="Calculate automatically"></td>
          <td><input type="hidden" name="$form->{ARAP}_tax_$item"
                id="$form->{ARAP}_tax_$item"
                value="$item" />$item--$form->{"${item}_description"}</td>
    </tr>
|;

        $form->hide_form(
            "${item}_rate",      "${item}_description",
            "${item}_taxnumber", "select$form->{ARAP}_tax_$item",
            "taxsource_$item"
            );
    }

    my $formatted_invtotal =
      $form->format_amount( \%myconfig, $form->{invtotal}, LedgerSMB::Setting->new(%$form)->get('decimal_places') );

    $form->hide_form( "oldinvtotal", "oldtotalpaid", "taxaccounts" );

     $selectARAP = $form->{"select$form->{ARAP}"};
     if ($form->{$form->{ARAP}}) {
         $selectARAP =~ s/(\Qoption value="$form->{$form->{ARAP}}"\E)/$1 selected="selected"/;
     }
    print qq|
        <tr class="transaction-line $form->{ARAP} total" id="line-total">
      <th align=left>$formatted_invtotal</th>
     <td>| . (($form->{currency} ne $form->{defaultcurrency})
              ? $form->format_amount(
                  \%myconfig,
                  $form->{invtotal} * $form->{exchangerate},
                  LedgerSMB::Setting->new(%$form)->get('decimal_places')) : '') . qq|</td>
     <td><select data-dojo-type="dijit/form/Select" name="$form->{ARAP}" id="$form->{ARAP}">
                 $selectARAP
              </select></td>
        </tr>
        <tr>
           <td>&nbsp;</td>
           <td>&nbsp;</td>
           <th align=left>| . $locale->text('Notes') . qq|</th>
           <th align=left>| . $locale->text('Internal Notes') . qq|</th>
        </tr>
    <tr>
           <td>&nbsp;</td>
           <td>&nbsp;</td>
      <td>$notes</td>
          <td>$intnotes</td>
    </tr>
      </table>
    </td>
  </tr>

  <tr class=listheading id="transaction-payments-label">
    <th class=listheading>| . $locale->text('Payments') . qq|</th>
  </tr>

  <tr>
    <td>
      <table width=100% id="invoice-payments-table">
|;

    if ( $form->{currency} eq $form->{defaultcurrency} ) {
        @column_index = qw(datepaid source memo paid ARAP_paid);
    }
    else {
        @column_index = qw(datepaid source memo paid exchangerate paidfx ARAP_paid);
    }

    $column_data{datepaid}     = "<th>" . $locale->text('Date') . "</th>";
    $column_data{paid}         = "<th>" . $locale->text('Amount') . "</th>";
    $column_data{exchangerate} = "<th>" . $locale->text('Exch') . "</th>";
    $column_data{paidfx}       = "<th>" . $form->{defaultcurrency} . "</th>";
    $column_data{ARAP_paid}    = "<th>" . $locale->text('Account') . "</th>";
    $column_data{source}       = "<th>" . $locale->text('Source') . "</th>";
    $column_data{memo}         = "<th>" . $locale->text('Memo') . "</th>";

    print qq|
        <tr>
|;

    for (@column_index) { print "$column_data{$_}\n" }

    print "
        </tr>
";

     # add 0 to numify the value in paid_$paidaccounts...
    $form->{paidaccounts}++ if ( defined $form->{"paid_$form->{paidaccounts}"}
                                 and $form->{"paid_$form->{paidaccounts}"}+0 );
    if (defined $form->{cash_accno}) {
        $form->{"select$form->{ARAP}_paid"} =~ /value="(\Q$form->{cash_accno}\E--[^<]*)"/;
        $form->{"$form->{ARAP}_paid_$form->{paidaccounts}"} = $1;
    }
    foreach my $i ( 1 .. $form->{paidaccounts} ) {

        $form->hide_form("cleared_$i");

        print q|
        <tr class="invoice-payment">
|;

        $form->{"select$form->{ARAP}_paid_$i"} =
            $form->{"select$form->{ARAP}_paid"};
        if ($form->{"$form->{ARAP}_paid_$i"}) {
            $form->{"select$form->{ARAP}_paid_$i"} =~
                s/(value="\Q$form->{"$form->{ARAP}_paid_$i"}\E")/$1 selected="selected"/;
        }

        # format amounts
        $form->{"paidfx_$i"} = $form->format_amount(
            \%myconfig,
            ($form->{"paid_$i"} // 0) * ($form->{"exchangerate_$i"} // 1) , LedgerSMB::Setting->new(%$form)->get('decimal_places') );
        $form->{"paid_$i"} =
          $form->format_amount( \%myconfig, $form->{"paid_$i"}, LedgerSMB::Setting->new(%$form)->get('decimal_places') );
        $form->{"exchangerate_$i"} =
          $form->format_amount( \%myconfig, $form->{"exchangerate_$i"} );

        $exchangerate = qq|&nbsp;|;
        if ( $form->{currency} ne $form->{defaultcurrency} ) {
            if ( $form->{"forex_$i"} ) {
                $form->hide_form("exchangerate_$i");
                $exchangerate = qq|$form->{"exchangerate_$i"}|;
            }
            else {
                $exchangerate =
qq|<input data-dojo-type="dijit/form/TextBox" name="exchangerate_$i" size=10 value=$form->{"exchangerate_$i"}>|;
            }
        }

        $form->hide_form("forex_$i");

        $form->{"datepaid_$i"} //= '';
        $form->{"source_$i"} //= '';
        $form->{"memo_$i"} //= '';
        $column_data{paid} =
qq|<td align=center><input data-dojo-type="dijit/form/TextBox" name="paid_$i" id="paid_$i" size=11 value=$form->{"paid_$i"}></td>|;
        $column_data{ARAP_paid} =
qq|<td align=center><select data-dojo-type="lsmb/FilteringSelect" name="$form->{ARAP}_paid_$i" id="$form->{ARAP}_paid_$i">$form->{"select$form->{ARAP}_paid_$i"}</select></td>|;
        $column_data{exchangerate} = qq|<td align=center>$exchangerate</td>|;
        $column_data{paidfx} = qq|<td align=center>$form->{"paidfx_$i"}</td>|;
        $column_data{datepaid} =
qq|<td align=center><input class="date" data-dojo-type="lsmb/DateTextBox" name="datepaid_$i" id="datepaid_$i" size=11 value=$form->{"datepaid_$i"}></td>|;
        $column_data{source} =
qq|<td align=center><input data-dojo-type="dijit/form/TextBox" name="source_$i" id="source_$i" size=11 value="$form->{"source_$i"}"></td>|;
        $column_data{memo} =
qq|<td align=center><input data-dojo-type="dijit/form/TextBox" name="memo_$i" id="memo_$i" size=11 value="$form->{"memo_$i"}"></td>|;

        for (@column_index) { print qq|$column_data{$_}\n| }

        print "
        </tr>
";
    }

    $form->hide_form( "paidaccounts", 'cash_accno' );

    print qq|
      </table>
    </td>
  </tr>
  <tr>
    <td><hr size=3 noshade></td>
  </tr>
</table>
|;

}

sub form_footer {
    $form->hide_form(qw(callback path login sessionid form_id));

    $transdate = $form->datetonum( \%myconfig, $form->{transdate} );

    # type=submit $locale->text('Update')
    # type=submit $locale->text('Print')
    # type=submit $locale->text('Post')
    # type=submit $locale->text('Schedule')
    # type=submit $locale->text('Ship to')
    # type=submit $locale->text('Post as new')
    # type=submit $locale->text('Delete')

    if ( !$form->{readonly} ) {
        my $printops = &print_options;
        my $formname = { name => 'formname',
                     options => [
                                  {text=> $locale->text('Transaction'), value => 'transaction'},
                                ]
                   };
        my $hold_text;

        if ($form->{on_hold}) {
            $hold_text = $locale->text('Off Hold');
        } else {
            $hold_text = $locale->text('On Hold');
        }

# REMARK: According to the check below, post_as_new and delete button never render
# Why post_as_new and delete are exist?
        %button = (
            'update' => { ndx => 1, key => 'U', value => $locale->text('Update') },
            'copy_to_new' => { ndx => 2, key => 'C', value => $locale->text('Copy to New') },
            'print' =>
              { ndx => 3, key => 'P', value => $locale->text('Print'),
                type => 'lsmb/PrintButton' },
            'edit_and_save' => { ndx   => 4, key   => 'E', value => $locale->text('Save') },
            'post' => { ndx => 5, key => 'O', value => $locale->text('Post') },
            'post_as_new' => { ndx => 6, key => 'O', value => $locale->text('Post') },
            'approve' => { ndx   => 7, key   => 'O', value => $locale->text('Post') },
            'schedule' =>
              { ndx => 8, key => 'H', value => $locale->text('Schedule') },
            'delete' =>
              { ndx => 9, key => 'D', value => $locale->text('Delete') },
            'on_hold' =>
              { ndx => 10, key => 'O', value => $hold_text },
            'save_info' =>
              { ndx => 11, key => 'I', value => $locale->text('Save Info') },
            'save_temp' =>
              { ndx => 12, key => 'T', value => $locale->text('Save Template')},
            'new_screen' => # Create a blank ar/ap invoice.
             { ndx => 13, key=> 'N', value => $locale->text('New') }
        );
        my $is_draft = 0;
        if (!$form->{approved} && !$form->{batch_id}){
           $is_draft = 1;
           if (!$form->is_allowed_role(['draft_modify'])){
               delete $button{edit_and_save};
           }
# Approve button should not render if user don't have permission
           if (!$form->is_allowed_role(['draft_post'])) {
             delete $button{approve};
           }
           delete $button{post_as_new};
           delete $button{post};
        }
        else {
            delete $button{approve};
            delete $button{edit_and_save};
        }

        if ($form->{separate_duties} || $form->{batch_id}){
            $button{post}->{value} = $locale->text('Save');
            $button{post_as_new}->{value} = $locale->text('Save as New');
            $form->hide_form('separate_duties');
        }
        if ( $form->{id}) {
            for ( "post", "delete", "post_as_new" ) {
                delete $button{$_};
            }
            delete $button{'update'} unless $is_draft;
        }
        elsif (!$form->{id}) {

            for ( "post_as_new","delete","save_info",
                  "print", 'copy_to_new', 'new_screen', 'on_hold') {
                delete $button{$_};
            }

            if ( $transdate && $form->is_closed( $transdate ) ) {
                for ( "post","save_info") {
                    delete $button{$_};
                }
            }
        }

        if (defined $button{'print'}) {
            # Don't show the print selectors, if there's no "Print" button
            print_select($form, $formname);
            print_select($form, $printops->{lang});
            print_select($form, $printops->{format});
            print_select($form, $printops->{media});
        }
        print "<br>";

        for ( sort { $button{$a}->{ndx} <=> $button{$b}->{ndx} } keys %button )
        {
            $form->print_button( \%button, $_ );
        }

    }
    if ($form->{id}){
        print qq|
<a href="pnl.pl?action=generate_income_statement&pnl_type=invoice&id=$form->{id}">[| . $locale->text('Profit/Loss') . qq|]</a><br />
<table width="100%">
<tr class="listtop">
<th colspan="4">| . $locale->text('Attached and Linked Files') . qq|</th>
<tr class="listheading">
<th>| . $locale->text('File name') . qq|</th>
<th>| . $locale->text('File type') . qq|</th>
<th>| . $locale->text('Attached at') . qq|</th>
<th>| . $locale->text('Attached by') . qq|</th>
</tr> |;
        foreach my $file (@{$form->{files}}){
              print qq|
<tr>
<td><a href="file.pl?action=get&file_class=1&ref_key=$form->{id}&id=$file->{id}"
       target="_download">$file->{file_name}</a></td>
<td>$file->{mime_type}</td>
<td>|. $file->{uploaded_at} .qq|</td>
<td>$file->{uploaded_by_name}</td>
</tr>
              |;
        }
        print qq|
<table width="100%">
<tr class="listheading">
<th>| . $locale->text('File name') . qq|</th>
<th>| . $locale->text('File type') . qq|</th>
<th>| . $locale->text('Attached To Type') . qq|</th>
<th>| . $locale->text('Attached To') . qq|</th>
<th>| . $locale->text('Attached at') . qq|</th>
<th>| . $locale->text('Attached by') . qq|</th>
</tr>|;
       foreach my $link (@{$form->{file_links}}){
            $aclass="&nbsp;";
            if ($link.src_class == 1){
                $aclass="Transaction";
            } elsif ($link.src_class == 2){
                $aclass="Order";
            }
            print qq|
<tr>
<td> $file->{file_name} </td>
<td> $file->{mime_type} </td>
<td> $aclass </td>
<td> $file->{reference} </td>
<td> | . $file->{attached_at}->to_output . qq| </td>
<td> $file->{attached_by} </td>
</tr>|;
       }
       print qq|
</table>|;
       $callback = $form->escape(
               lc($form->{ARAP}) . ".pl?action=edit&id=".$form->{id}
       );
       print qq|
<a href="file.pl?action=show_attachment_screen&ref_key=$form->{id}&file_class=1&callback=$callback"
   >[| . $locale->text('Attach') . qq|]</a>|;
    }

    print qq|
</form>
| . $form->close_status_div . qq|
</body>
</html>
|;
}

sub on_hold {
    use LedgerSMB::IS;
    use LedgerSMB::IR; # TODO: refactor this over time

    if ($form->{id}) {
        if ($form->{ARAP} eq 'AR'){
            my $toggled = IS->toggle_on_hold($form);
        } else {
            my $toggled = IR->toggle_on_hold($form);
        }
        &edit();
    }
}


sub save_temp {
    my $lsmb = { %$form };
    $lsmb->{is_invoice} = 1;
    $lsmb->{due} = $form->{invtotal};
    $lsmb->{credit_id} = $form->{customer_id} // $form->{vendor_id};
    my ($department_name, $department_id) = split/--/, $form->{department};
     if (!$lsmb->{language_code}){
        delete $lsmb->{language_code};
    }
    $lsmb->{credit_id} = $form->{"$form->{vc}_id"};
    $lsmb->{department_id} = $department_id;
    if ($form->{ARAP} eq 'AR'){
        $lsmb->{entity_class} = 2;
    } else {
        $lsmb->{entity_class} = 1;
    }
    $lsmb->{post_date} = $form->{transdate};
    for my $iter (0 .. $form->{rowcount}){
        if ($form->{"AP_amount_$iter"} and
                  ($form->{"amount_$iter"} != 0)){
             my ($acc_id, $acc_name) = split /--/, $form->{"AP_amount_$iter"};
             my $amount = $form->{"amount_$iter"};
             push @{$lsmb->{journal_lines}},
                  {accno => $acc_id,
                   amount => $amount,
                   cleared => 'false',
                  };
        }
    }
    $template = LedgerSMB::DBObject::TransTemplate->new(%$lsmb);
    $template->save;
    $form->redirect( $locale->text('Template Saved!') );
}

sub edit_and_save {
    my $draft = LedgerSMB::DBObject::Draft->new(%$form);
    $draft->delete();
    delete $form->{id};
    AA->post_transaction( \%myconfig, \%$form );
    $form->{rowcount} = 0;
    $form->{paidaccounts} = 0;
    edit();
}

sub approve {
    $form->update_invnumber;

    my $draft = LedgerSMB::DBObject::Draft->new(%$form);

    $draft->approve();

    if ($form->{callback}){
        print "Location: $form->{callback}\n";
        print "Status: 302 Found\n\n";
        print qq|<html><body class="lsmb">|;
        my $url = $form->{callback};
        print qq|If you are not redirected automatically, click <a href="$url">|
                . qq|here</a>.</body></html>|;

    } else {
        $form->info($locale->text('Draft Posted'));
    }
}

sub update {
    my $display = shift;
    my $form_id = delete $form->{id};
    $form->open_form() unless $form->check_form();
    $is_update = 1;
        $form->{invtotal} = 0;

        $form->{exchangerate} =
          $form->parse_amount( \%myconfig, $form->{exchangerate} );

        @flds =
          ( "amount", "$form->{ARAP}_amount", "projectnumber", "description","taxformcheck" );
        $count = 0;
        @a     = ();
    foreach my $i ( 1 .. $form->{rowcount} ) {
            $form->{"amount_$i"} =
              $form->parse_amount( \%myconfig, $form->{"amount_$i"} );
            if ( $form->{"amount_$i"} ) {
                push @a, {};
                $j = $#a;

                for (@flds) { $a[$j]->{$_} = $form->{"${_}_$i"} }
                $count++;
            }
        }

        $form->redo_rows( \@flds, \@a, $count, $form->{rowcount} );
        $form->{rowcount} = $count + 1;

        for ( 1 .. $form->{rowcount} ) {
        if ( defined $form->{"amount_$_"} ) {
            $form->{invtotal} += $form->{"amount_$_"};
        }
    }

        if ( $newname = &check_name( $form->{vc} ) ) {
            $form->{notes} = $form->{intnotes} unless $form->{id};
            $form->rebuild_vc($form->{vc}, $form->{transdate});
        }
        if ( $form->{transdate} ne $form->{oldtransdate} ) {
            $form->{duedate} =
              $form->current_date( \%myconfig, $form->{transdate},
                $form->{terms} * 1 );
            $form->{oldtransdate} = $form->{transdate};
            $newproj = $form->rebuild_vc($form->{vc}, $form->{transdate})
              if !$newname;
        }

    @taxaccounts = split / /, $form->{taxaccounts};

    for (@taxaccounts) {
        $form->{"tax_$_"} =
          $form->parse_amount( \%myconfig, $form->{"tax_$_"} );
        $form->{"calctax_$_"} = 1 if !$form->{invtotal};
    }

    my @taxaccounts = Tax::init_taxes($form, $form->{taxaccounts});
    my $tax = Tax::calculate_taxes( \@taxaccounts, $form, $form->{invtotal}, 0 );
    for (@taxaccounts) {
        if ($form->{'calctax_' . $_->account} && $is_update) {
            $form->{'tax_' . $_->account} = $_->value;
        }
        $form->{invtotal} += $_->value;
    }



    my $j = 1;
    my $totalpaid = LedgerSMB::PGNumber->bzero();
    foreach my $i ( 1 .. $form->{paidaccounts} ) {
        if ( $form->{"paid_$i"} and $form->{"paid_$i"} != 0 ) {
            for (qw(datepaid source memo cleared)) {
                $form->{"${_}_$j"} = $form->{"${_}_$i"};
            }
            for (qw(paid exchangerate)) {
                $form->{"${_}_$j"} =
                  $form->parse_amount( \%myconfig, $form->{"${_}_$i"} );
            }

            $totalpaid += $form->{"paid_$j"};

            if ( $j++ != $i ) {
                for (qw(datepaid source memo paid exchangerate forex cleared)) {
                    delete $form->{"${_}_$i"};
                }
            }
        }
        else {
            for (qw(datepaid source memo paid exchangerate forex cleared)) {
                delete $form->{"${_}_$i"};
            }
        }
    }
    $form->{paidaccounts} = $j;

    $form->{creditremaining} -=
      ( $form->parse_amount(\%myconfig, $form->{invtotal})
        - $form->parse_amount(\%myconfig, $totalpaid)
        + $form->parse_amount(\%myconfig, $form->{oldtotalpaid})
        - $form->parse_amount(\%myconfig, $form->{oldinvtotal}) );
    $form->{oldinvtotal}  = $form->{invtotal};
    $form->{oldtotalpaid} = $totalpaid;

    &create_links;
    $form->generate_selects(\%myconfig);
    $form->{id} = $form_id;
    &display_form;

}

sub post {
    if (!$form->close_form){
       $form->info(
          $locale->text('Data not saved.  Please try again.')
       );
       &update;
       $form->finalize_request();
    }
    if (!$form->{duedate}){
          $form->{duedate} = $form->{transdate};
    }
    $label =
      ( $form->{vc} eq 'customer' )
      ? $locale->text('Customer missing!')
      : $locale->text('Vendor missing!');

    # check if there is an invoice number, invoice and due date
    $form->isblank( "transdate", $locale->text('Invoice Date missing!') );
    $form->isblank( "duedate",   $locale->text('Due Date missing!') );
    #$form->isblank( "crdate",    $locale->text('Invoice Created Date missing!') );
    # pongraczi: we silently fill crdate with transdate if the user left empty to do not break existing workflow
    if (!$form->{crdate}){
          $form->{crdate} = $form->{transdate};
    }

    $form->isblank( $form->{vc}, $label );

    $transdate = $form->datetonum( \%myconfig, $form->{transdate} );

    $form->error(
        $locale->text('Cannot post transaction for a closed period!') )
        if ( $form->is_closed( $transdate ) );

    $form->isblank( "exchangerate", $locale->text('Exchange rate missing!') )
      if ( $form->{currency} ne $form->{defaultcurrency} );

    foreach my $i ( 1 .. $form->{paidaccounts} ) {
        if ( $form->{"paid_$i"} and $form->{"paid_$i"} != 0) {
            $datepaid = $form->datetonum( \%myconfig, $form->{"datepaid_$i"} );

            $form->isblank( "datepaid_$i",
                $locale->text('Payment date missing!') );

            $form->error(
                $locale->text('Cannot post payment for a closed period!') )
                if ( $form->is_closed( $datepaid ) );

            if ( $form->{currency} ne $form->{defaultcurrency} ) {
                $form->{"exchangerate_$i"} = $form->{exchangerate}
                  if ( $transdate == $datepaid );
                $form->isblank( "exchangerate_$i",
                    $locale->text('Exchange rate for payment missing!') );
            }
        }
    }

    # if oldname ne name redo form
    ($name) = split /--/, $form->{ $form->{vc} };
    if ( $form->{"old$form->{vc}"} ne qq|$name--$form->{"$form->{vc}_id"}|
         and $form->{"old$form->{vc}"} ne $name) {
        $form->info('Data changed on Post; form recalculated. Please re-post.');
        &update;
        $form->finalize_request();
    }

    if ( !$form->{repost} ) {
        if ( $form->{id} ) {
            &repost;
            $form->finalize_request();
        }
    }



    if ( AA->post_transaction( \%myconfig, \%$form ) ) {

        $form->update_status;
       if ( $form->{printandpost} ) {
           &{"print_$form->{formname}"}( $old_form, 1 );
        }

        if(defined($form->{batch_id}) and $form->{batch_id}
           and ($form->{callback} !~ /vouchers/)) {
            $form->{callback}.= qq|&batch_id=$form->{batch_id}|;
    }
        $form->{rowcount} = 0;
        $form->{paidaccounts} = 0;
            edit();
        }
    else {
        $form->error( $locale->text('Cannot post transaction!') );
    }

}#post end

# New Function Body starts Here



sub save_info {

        my $taxformfound=0;

        $taxformfound=AA->taxform_exist($form,$form->{"$form->{vc}_id"});
            $form->{arap} = lc($form->{ARAP});
        AA->save_intnotes($form);
        AA->save_employee($form);

        foreach my $i(1..($form->{rowcount}))
        {

        if($form->{"taxformcheck_$i"} and $taxformfound)
        {

          AA->update_ac_tax_form($form,$form->{dbh},$form->{"entry_id_$i"},"true") if($form->{"entry_id_$i"});

        }
        else
        {

            AA->update_ac_tax_form($form,$form->{dbh},$form->{"entry_id_$i"},"false") if($form->{"entry_id_$i"});

        }

        }

        if ($form->{callback}){
        print "Location: $form->{callback}\n";
        print "Status: 302 Found\n\n";
        print qq|<html><body class="lsmb">|;
        my $url = $form->{callback};
        print qq|If you are not redirected automatically, click <a href="$url">|
            . qq|here</a>.</body></html>|;

        } else {
        $form->info($locale->text('Draft Posted'));
        }

}

1;

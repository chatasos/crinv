#!/usr/bin/perl
###############################################################################
# crinv (Create Inventory Report) v1.1 (23-Sep-2011)
# Copyright (c) 2009-2011 Tassos (http://ccie-in-3-months.blogspot.com/)
#
# crinv is a perl script that processes a text file with a list of devices (routers & switches),
# then it gets info from them by using the SNMP Entity-MIB,
# and finally it creates a csv file with parts info per device in a kind of hierarchical format.
#
# History
#--------
# v0.1 30/10/2009 initial version
# v0.2 04/11/2009 multiple devices supported
#                 device name added to output
#                 filtering added to model name
#                 minor improvements
# v0.9 10/01/2010 major rewrite
#                 external snmp script deprecated
#                 Net::SNMP integration
#                 uploaded to code.google.com
#
# v1.0 28/09/2010 minor bug fixes
#
# v1.1 23/09/2011 error output is redirected to two files for later processing
#                 some extra checks added while reading/writing files
# v1.2 24/02/2019 uploaded to github
###############################################################################

use strict;
use warnings;
use Getopt::Std; 		# For the processing of the command line options
#use diagnostics -verbose;	# For diagnostics
use Data::Dumper;		# For dumping variables
#use Switch;
#use XML::Dumper;
use Net::SNMP;			# For SNMP polling

##################################
# user defined variables
##################################

# Default Community used for SNMP requests
# set this to a default value, if you don't want to put it into a file or give it as a cli option
my $def_community_name = 'public';

# define various display filters
my $display_dev_name = 1;	# Whether to display the device name in the leftmost column

my $left_space = " ";		# You can use "\t" for more clarity (although Excel has issues with tab) or "" for no space at all
my $display_level = 1;		# Whether to make the ouput seem hierarchical ($left_space must not be empty)

my $display_id = 0;		# Whether to display the Id from OID (usually not needed)
my $display_descr = 1;		# Whether to display the Description
my $display_name = 1;		# Whether to display the Name
my $display_ser_num = 1;	# Whether to display the SerialNumber
my $display_hw_rev = 0;		# Whether to display the HardwareRevision
my $display_fw_rev = 0;		# Whether to display the FirmwareRevision
my $display_sw_rev = 1;		# Whether to display the SoftwareRevision
my $display_model = 1;		# Whether to display the ModelName

my $output_mode = 1;		# 0 = print all details for all parts
				# 1 = print all details for parts with a ModelName (default)
				# 2 = print only ModelName & SerialNumber for parts with a ModelName

my $check_filter = 0;		# Whether to filter all parts included in the @filter_parts

# put here any ModelName that you don't want to process and display
my @filter_parts = (
	'WS-C6K-VTT',
	'WS-C6000-CL',
	'WS-C6K-VTT-E',
	'CLK-7600',

	'0       0       0',
	'Hex: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF',
	'0xffffffffffffffffffffffffffffffffffffffff',
	'H11F990',
	'H11F833',
	'H11F841',
	'H11F790',
	'H11F861',
	'H11F930',
	'H11F914',
	'H11F921',
	'H11H386',
	
	'N/A',

	'7600-MSFC4',
	'7600-PFC3CXL',
	'WS-SUP720',
	'WS-F6K-PFC3BXL',
	'WS-F6K-PFC3B',

	'7600-ES+20G',
	'7600-ES+3CXL',
	
	'GBIC_LX',
	'GBIC_T',
	'XENPAK-10GB-LR',
	'XENPAK-10GB-LR+',
	'X2-10GB-LR',
	'SFP-OC3-IR1',
	'XFP-10GLR-OC192SR',
	
	'ESR-PRE-MEM-FD128',
	'ESR-PRE-MEM-FD48',
	'MEM-NPE-G1-FLD64',
	'MEM-NPE-G2-FLD256',
	
	'ESR-BLOWER',
);
	
#################################
# MAIN PROGRAM STARTS FROM HERE #
#################################

my $PROG_NAME      = $0; 
my $PROG_DESC      = 'crinv (Create Inventory Report)';
my $AUTHOR         = 'Tassos (http://ccie-in-3-months.blogspot.com/)';
my $VERSION        = "v1.2";
my $VERSION_DATE   = "24-Feb-2019";


#####################
# check for arguments
#####################

if (!@ARGV) { &help; }

my %opts;
getopts('d:c:h', \%opts);

if ( defined $opts{h} ) { &help; }

my $file_input;		# file that contains the list of devices to be polled
my $file_output;	# file that contains the generated report of part numbers per device
my $file_snmperror;	# file that contains the list of devices that returned error in SNMP walk
my $file_snmpnull;	# file that contains the list of devices that returned null in SNMP walk
my $file_snmpother;	# file that contains the list of devices that returned other error in SNMP walk

if ( defined $opts{d} ) {
	$file_input  = $opts{d};

	# create the output files by removing the extension from the input file and adding a new one to it
	my $filename = ( index ($file_input, ".") > -1 ) ? substr ($file_input, 0, rindex($file_input, ".")) : $file_input;

	$file_output    = $filename.".csv";
	$file_snmperror = $filename."-error.txt";
	$file_snmpnull  = $filename."-null.txt";
	$file_snmpother = $filename."-other.txt";
} else {
	print "No devices file given. Please use the -d option or use -h for help.\n";
	exit 1;
}

my $community_name = ( defined $opts{c} ) ? $opts{c} : $def_community_name;

#######################
# define more variables
#######################

my $snmp_success = 0;

my %hash_devices = ();

my $dev_name = '';
my $dev_community = '';

my $top_header = '';	# top row of output
my $left_header = '';	# left column of output

my $entry;
my $hash_key;
my $hash_value;

my $OID_entPhysicalTable = '1.3.6.1.2.1.47.1.1.1.1';
my $regexp_entPhysicalTable = '1.3.6.1.2.1.47.1.1.1.1.(\d+).(\d+)';

# my %entPhysicalIndex;			# 1.3.6.1.2.1.47.1.1.1.1.1 (not supported)
my %entPhysicalDescr;			# 1.3.6.1.2.1.47.1.1.1.1.2	= Cisco ASR1000 Route Processor 2
my %entPhysicalContainedIn;		# 1.3.6.1.2.1.47.1.1.1.1.4
my %entPhysicalClass;			# 1.3.6.1.2.1.47.1.1.1.1.5
# my %entPhysicalParentRelPos;		# 1.3.6.1.2.1.47.1.1.1.1.6 (not used)
my %entPhysicalName;			# 1.3.6.1.2.1.47.1.1.1.1.7	= module R0
my %entPhysicalHardwareRev;		# 1.3.6.1.2.1.47.1.1.1.1.8	= V01
my %entPhysicalFirmwareRev;		# 1.3.6.1.2.1.47.1.1.1.1.9	= 12.2(33r)XNC0
my %entPhysicalSoftwareRev;		# 1.3.6.1.2.1.47.1.1.1.1.10	= 02.04.02.122-33.XND2
my %entPhysicalSerialNum;		# 1.3.6.1.2.1.47.1.1.1.1.11	= XXX11111XXX
my %entPhysicalModelName;		# 1.3.6.1.2.1.47.1.1.1.1.13	= ASR1000-RP2
my %entPhysicalIsFRU;			# 1.3.6.1.2.1.47.1.1.1.1.16


###################
# interrupt handler
###################

foreach (qw(INT QUIT KILL)) {
        $SIG{$_} = sub {
        print "\nProgram execution aborted...: $! \n\n";

	# uncomment for debug reasons only
        #print Dumper(%entPhysicalDescr);

        generate_report();

	close (SNMPERROR) or warn "Close failed: $!";
	close (SNMPNULL) or warn "Close failed: $!";
	close (SNMPOTHER) or warn "Close failed: $!";

        exit 1;
        }
}


#########
# BEGIN #
#########

print "\n";
print "$PROG_DESC $VERSION ($VERSION_DATE)\n";
#print "$AUTHOR\n";
print "---------------------------------------------------\n";

#######################
# read the devices file
#######################

read_file($file_input);

print "Found " . scalar(keys %hash_devices) . " valid devices in '$file_input'...\n";
print "------------------------------\n";

###################
# get the snmp data
###################

print "Collecting snmp data...\n";

# open error files for writing
open (SNMPERROR, ">$file_snmperror") or die "ERROR while trying to open file >$file_snmperror for writing\n";
open (SNMPNULL,  ">$file_snmpnull")  or die "ERROR while trying to open file >$file_snmpnull for writing\n";
open (SNMPOTHER, ">$file_snmpnull")  or die "ERROR while trying to open file >$file_snmpother for writing\n";

# Create a session for each device and issue a get_table request for each one of them
for $dev_name (sort keys %hash_devices) {

	print "Getting snmp data from '$dev_name'...\n";
	
	$dev_community = $hash_devices{$dev_name};
   
	my ($session, $error) = Net::SNMP->session(
		-hostname  => $dev_name,
		-community => $dev_community,
		-version   => 'snmpv2c',
	);

	if (!defined $session) {
		printf "ERROR: Failed to create snmp session for device '%s': %s.\n", $dev_name, $error;
		next;
	}

	my $result = $session->get_table(
		-baseoid          => $OID_entPhysicalTable,
		#-maxrepetitions  => 10,  # v2c/v3
	);

	# check for errors in SNMP walk 
	if (!defined $result) {
		printf "ERROR: Failed to get entPhysicalTable from device '%s': %s.\n", $session->hostname(), $session->error();

		if ( $session->error() =~ /No response from remote host/ ) {
			print SNMPERROR "$dev_name\n";
		} elsif ( $session->error() =~ /The requested table is empty or does not exist/ ) {
			print SNMPNULL "$dev_name\n";
		} else {
			print SNMPOTHER "$dev_name\n";
		}

		#switch ( $session->error() ) {
		#	case /No response from remote host/ 
		#		{ print SNMPERROR "$dev_name\n" }
		#	case /The requested table is empty or does not exist/ 
		#		{ print SNMPNULL "$dev_name\n" }
		#	else 
		#		{ print SNMPOTHER "$dev_name\n"}
		#}
		
		next;
	}

	$session->close();
	
	snmp_dispatcher();
	
	if ( (defined $session) && (defined $result) ) {
		print "OK!\n";
		$snmp_success = 1;
	}
	
	# store the collected data into various hashes for further processing
	for my $oid (sort keys %$result ) {
		if ( $oid =~ /$regexp_entPhysicalTable/ ) {
			$entry = $1;
			$hash_key = $2;
			$hash_value = $result->{$oid};		# ${$result}{$oid} can be used too
			
			$hash_value =~ s/^[\s"]*//;		# remove all spaces and quotes from the start
			$hash_value =~ s/[\s"]*$//;		# remove all spaces and quotes from the end
			#$hash_value =~ s/["]* Hex: .*$//;	# remove some ugly chars from the end

			if ( $entry == 2 ) {
				$entPhysicalDescr{$dev_name}{$hash_key} = $hash_value;
			} elsif ( $entry == 4 ) {
				$entPhysicalContainedIn{$dev_name}{$hash_key} = $hash_value;
			} elsif ( $entry == 5 ) {
				$entPhysicalClass{$dev_name}{$hash_key} = $hash_value;
			} elsif ( $entry == 7 ) {
				$entPhysicalName{$dev_name}{$hash_key} = $hash_value;
			} elsif ( $entry == 8 ) {
				$entPhysicalFirmwareRev{$dev_name}{$hash_key} = $hash_value;
			} elsif ( $entry == 9 ) {
				$entPhysicalFirmwareRev{$dev_name}{$hash_key} = $hash_value;
			} elsif ( $entry == 10 ) {
				$entPhysicalSoftwareRev{$dev_name}{$hash_key} = $hash_value;
			} elsif ( $entry == 11 ) {
				$entPhysicalSerialNum{$dev_name}{$hash_key} = $hash_value;
			} elsif ( $entry == 13 ) {
				$entPhysicalModelName{$dev_name}{$hash_key} = $hash_value;
			} elsif ( $entry == 16 ) {
				$entPhysicalIsFRU{$dev_name}{$hash_key} = $hash_value;
			}

			#switch ( $entry ) {
			#	case ( 2 )  { $entPhysicalDescr{$dev_name}{$hash_key} = $hash_value; }
			#	case ( 4 )  { $entPhysicalContainedIn{$dev_name}{$hash_key} = $hash_value; }
			#	case ( 5 )  { $entPhysicalClass{$dev_name}{$hash_key} = $hash_value; }
			#	#case ( 6 )  { $entPhysicalParentRelPos{$dev_name}{$hash_key} = $hash_value; }
			#	case ( 7 )  { $entPhysicalName{$dev_name}{$hash_key} = $hash_value; }
			#	case ( 8 )  { $entPhysicalHardwareRev{$dev_name}{$hash_key} = $hash_value; }
			#	case ( 9 )  { $entPhysicalFirmwareRev{$dev_name}{$hash_key} = $hash_value; }
			#	case ( 10 ) { $entPhysicalSoftwareRev{$dev_name}{$hash_key} = $hash_value; }
			#	case ( 11 ) { $entPhysicalSerialNum{$dev_name}{$hash_key} = $hash_value; }
			#	case ( 13 ) { $entPhysicalModelName{$dev_name}{$hash_key} = $hash_value; }
			#	case ( 16 ) { $entPhysicalIsFRU{$dev_name}{$hash_key} = $hash_value; }
			#}
		}
	}
}

# close open files
close (SNMPERROR) or warn "Close failed: $!";
close (SNMPNULL) or warn "Close failed: $!";
close (SNMPOTHER) or warn "Close failed: $!";

#print Dumper(%entPhysicalDescr);

#exit;

if ( $snmp_success ) {
	print "Finished collecting snmp data!\n";
	print "------------------------------\n";
} else {
	print "Snmp requests to all devices have failed!\n";
	print "------------------------------\n";
	exit;
}

#######################
# process the snmp data
#######################

print "Processing snmp data...\n";
	
# parse entPhysicalContainedIn and create a tree-like hash of arrays
# where the new key is the old value and the new value is an array of all the old keys
# this way a hierarchical map of parts can be easily created later
#
# 1st key is the device name
# 2nd key is the part id
# value is an array of part-ids belonging under the part-id of 2nd key
#
# i.e.
# $VAR7 = 'router1';
# $VAR8 = {
#           '4143' => [ '4144'],          
#           '7010' => [ '7014',
#                       '7011',
#                       '7015',
#                       '7016',
#                       '7017',
#                       '7013'
#                      ]
 
my %hash_entPhysicalTree;
#my %hash_entPhysicalEntry;

for my $device (keys %entPhysicalContainedIn ) {
	for my $part_id ( keys %{$entPhysicalContainedIn{$device}} ) {
		# push each new key into the new hash's array
		$hash_key = $entPhysicalContainedIn{$device}{$part_id};
		push @{ $hash_entPhysicalTree{$device}{$hash_key} }, $part_id;

	# create a new hash that includes everything for future XML/HTML usage
	#$hash_entPhysicalEntry{$device}{$hash_key}{Id}			= $hash_key;
	#$hash_entPhysicalEntry{$device}{$hash_key}{Name}		= $entPhysicalName{$device}{$hash_key};
	#$hash_entPhysicalEntry{$device}{$hash_key}{ModelName}		= $entPhysicalModelName{$device}{$hash_key};
	#$hash_entPhysicalEntry{$device}{$hash_key}{Descr}		= $entPhysicalDescr{$device}{$hash_key};
	#$hash_entPhysicalEntry{$device}{$hash_key}{SerialNum}		= $entPhysicalSerialNum{$device}{$hash_key};
	#$hash_entPhysicalEntry{$device}{$hash_key}{FirmwareRev}	= $entPhysicalFirmwareRev{$device}{$hash_key};
	#$hash_entPhysicalEntry{$device}{$hash_key}{SoftwareRev}	= $entPhysicalSoftwareRev{$device}{$hash_key};
	}
}

print "Finished processing snmp data!\n";
print "------------------------------\n";
print "Generating report...\n";

#print Dumper(%hash_entPhysicalTree);

#exit;

###################
# generate report
###################
sub generate_report
{

open (REPORT, ">$file_output") or die "ERROR while trying to open file >$file_output for writing\n";

# check $output_mode
if ( $output_mode == 2 ) {
	$display_id = 0;
	$display_descr = 0;
	$display_name = 0;
	$display_hw_rev = 0;
	$display_fw_rev = 0;
	$display_sw_rev = 0;
}

# Create and display the top header
$top_header .= ( $display_dev_name ) ? "DeviceName;" : '';
$top_header .= ( $display_id )       ? "Id;" : '';
$top_header .= ( $display_model )    ? "Model;" : '';
$top_header .= ( $display_descr )    ? "Description;" : '';
$top_header .= ( $display_name )     ? "Name;" : '';
$top_header .= ( $display_ser_num )  ? "SerialNumber;" : '';
$top_header .= ( $display_hw_rev )   ? "HwVersion;" : '';
$top_header .= ( $display_fw_rev )   ? "FwVersion;" : '';
$top_header .= ( $display_sw_rev )   ? "SwVersion;" : '';

print REPORT $top_header,"\n";

# Loop through each device (tree), printing its parts (branches)
for my $device (sort keys %hash_entPhysicalTree ) {

	print REPORT " ; ; \n";
	
	# start printing from 0 (root) of each device
	# this normally shouldn't be in a loop, since we have a single root per device
	# but i'm not 100% sure that all devices are like this

	for my $root ( @{ $hash_entPhysicalTree{$device}{'0'} } ) {
		print_branch($device, $root, 0);
	}

}

# get the time
my @months = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
my @weekDays = qw(Sun Mon Tue Wed Thu Fri Sat Sun);
my ($second, $minute, $hour, $dayOfMonth, $month, $yearOffset, $dayOfWeek, $dayOfYear, $daylightSavings) = localtime();
my $year = 1900 + $yearOffset;
my $the_time = "$hour:$minute:$second, $weekDays[$dayOfWeek] $months[$month] $dayOfMonth, $year";

print REPORT "\n\nReport generated by $PROG_DESC $VERSION at $the_time\n";
 
close (REPORT) or warn "Close failed: $!";

print "Finished generating report '$file_output'...\n";
print "------------------------------\n";

}

generate_report();

########################################
# test XML output
########################################
# my $dump = new XML::Dumper;
# $dump->pl2xml( \%hash_entPhysicalEntry, "dump.xml" );

exit;

#######
# END #
#######

# ------------------------------------------------------------------------------
# Name    : print_branch
# Comment : checks the display filters and prints a branch of a tree recursively
# Input   : $tree, $branch, $level
# Output  : -
# ------------------------------------------------------------------------------
sub print_branch
{
	my ($tree, $branch, $level) = @_;
	my $next_branch;
	
	my $name	= '';
	my $ser_num	= '';
	my $hw_rev	= '';
	my $fw_rev	= '';
	my $sw_rev	= '';
	my $descr	= '';
	my $model	= '';
	
	if ( $display_name ) {
		$name = ( exists($entPhysicalName{$tree}{$branch}) ) ? $entPhysicalName{$tree}{$branch}.';' : ';';
	}
	
	if ( $display_ser_num ) {
		$ser_num = ( exists($entPhysicalSerialNum{$tree}{$branch}) ) ? $entPhysicalSerialNum{$tree}{$branch}.';' : ';';
	}
	
	if ( $display_hw_rev ) {
		$hw_rev	= ( exists($entPhysicalHardwareRev{$tree}{$branch}) ) ? $entPhysicalHardwareRev{$tree}{$branch}.';' : ';';
	}
	
	if ( $display_fw_rev ) {
		$fw_rev = ( exists($entPhysicalFirmwareRev{$tree}{$branch}) ) ? $entPhysicalFirmwareRev{$tree}{$branch}.';' : ';';
	}
	
	if ( $display_sw_rev ) {
		$sw_rev = ( exists($entPhysicalSoftwareRev{$tree}{$branch}) ) ? $entPhysicalSoftwareRev{$tree}{$branch}.';' : ';';
	}
	
	if ( $display_descr ) {
		$descr = ( exists($entPhysicalDescr{$tree}{$branch}) ) ? $entPhysicalDescr{$tree}{$branch}.';' : ';';
	}
	
	if ( $display_model ) {
		$model = ( exists($entPhysicalModelName{$tree}{$branch}) ) ? $entPhysicalModelName{$tree}{$branch}.';' : ';';
	}

	my $left_header = ( $display_dev_name ) ? "$tree;" : '';
	my $lev = ( $display_level ) ? $level : '1';	# whether each level gets moved to the right
	my $id  = ( $display_id ) ? "$branch;" : '';	# whether to show the id included in the snmp oid
	
	# check if ModelName is included into the parts that have to be filtered
	# \Q\E are used in grep in order to "disable" any possible pattern metacharacters found in ModelName
	if ( $check_filter && $entPhysicalModelName{$tree}{$branch} && scalar grep(/^\Q$entPhysicalModelName{$tree}{$branch}\E$/, @filter_parts) ) {
		# skip/ignore the part
	} else {
		# create the appropriate output depending on $output_mode
		if ( $output_mode eq '2' && ( $model ne '' && $model ne ';' ) ) {
			print REPORT $left_header, $left_space x $lev, $model, $ser_num, "\n";
		} elsif ( $output_mode eq '1' && ( $model ne '' && $model ne ';' ) ) {
			print REPORT $left_header, $left_space x $lev, $id, $model, $descr, $name, $ser_num, $hw_rev, $fw_rev, $sw_rev, "\n";
		} elsif ( $output_mode eq '0' ) {
			print REPORT $left_header, $left_space x $lev, $id, $model, $descr, $name, $ser_num, $hw_rev, $fw_rev, $sw_rev, "\n";
		}
	}
	
	# continue to next branch in numerical order
	if ( exists $hash_entPhysicalTree{$tree}{$branch} ) {
		for $next_branch ( sort { $a <=> $b } @{ $hash_entPhysicalTree{$tree}{$branch} } ) {
			print_branch($tree, $next_branch, $level + 1);
		}
	}

	return;
}

# ------------------------------------------------------------------------------
# Name    : read_file
# Comment : reads a text file that contains a list of devices to poll 
#           and stores them into a hash
# Input   : filename
# Output  : -
# ------------------------------------------------------------------------------
sub read_file
{
	my ($file) = @_;
	my $line;
	
	open(TEXT_FILE, $file) or die "Can't open \"$file\" : $!\n";
	
	while ( $line = <TEXT_FILE> ) {
		chomp $line; 
		
		# remove all white spaces
		$line =~ s/\s//g;
		
		# ignore empty lines and comments
		if ( $line =~ /^[#\|]/ || $line eq '' ) { next; }
		
		# check data validity and get the device,community values
		if ( $line =~ /^(.+)\|(.*)$/ ) {
			$hash_devices{$1} = ( $2 ne '' ) ? $2 : $community_name;
		} else {
			$hash_devices{$line} = $community_name;
		}

	}

	close(TEXT_FILE) or warn "Close failed: $!";
}

# ------------------------------------------------------------------------------
# Name    : help
# Comment : displays a list of available options and other useful info
# Input   : no cli argument or "-h"
# Output  : help screen
# ------------------------------------------------------------------------------
sub help
{
    print "
    $PROG_DESC $VERSION ($VERSION_DATE)
    $AUTHOR
	
    Usage:
        $PROG_NAME -d file [-c community]

    Options:
     -d : file containing the devices' names and community per device (required)
     -c : community name that will be used for all devices (optional)
     -h : this help screen
    ";

    exit;
}

#########################################


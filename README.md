Create Inventory Report

crinv is a perl script that processes a text file with a list of devices (routers & switches),
then it gets info from them by using the SNMP Entity-MIB,
and finally it creates a csv file with parts info per device in a kind of hierarchical format.

Format of devices' file
-----------------------
 - The general format of each line is "device|community"
 - Only device is required, community is optional
 - All white spaces are removed before processing each line
 - Lines starting with # are comments and will be ignored
 - Lines starting with | are ignored
 - The | character must be used on each line for seperation between device and community
 - Devices without a community use the default/cli community
 - Lines without a | character are considered to be devices and use the default/cli community

Output csv filename is created automatically after removing any extension from the 
devices input filename and adding .csv to it

In order to make the output kind of hierarchical, you have to change the following two parameters inside the script:
 
my $left_space = " ";  # This can be any character(s) you want to use to produce the left indent effect
                        # spaces are prefered since tab characters do not show up in Excel
my $display_level = 1; # This must be 1 for hierarchical output

Examples:
---------
crinv -d devices.txt -c SNMP-COMM
     Process all devices from devices.txt and use SNMP-COMM as a community name for devices
     that don't have one
crinv -d devices.txt
     Process all devices from devices.txt and use the default community name for devices
     that don't have one

The following information can be included in the generated csv file:

entPhysicalDescr : A textual description of physical entity
entPhysicalName : The textual name of the physical entity
entPhysicalHardwareRev : The vendor-specific hardware revision string for the physical entity
entPhysicalFirmwareRev : The vendor-specific firmware revision string for the physical entity
entPhysicalSoftwareRev : The vendor-specific software revision string for the physical entity
entPhysicalSerialNum : The vendor-specific serial number string for the physical entity
entPhysicalModelName : The vendor-specific model name identifier string associated with this physical component

Check Entity MIB (ftp://ftp.cisco.com/pub/mibs/v2/ENTITY-MIB.my) for more details.

Please note that not all Cisco devices support the Entity MIB and those that support it, do not
always display the correct information.

The following modular devices have been tested (with latest IOS) and seem to return correct values:
6500, 7600, 10000, ASR1000, 12000.

The following smaller devices have been tested (with latest IOS) and seem to return correct values:
2950, 2960, ME3400, 3750, 3845, 7200/G1, 7200/G2. 7200s may show a different S/N than the actual one.

Required Perl modules:
----------------------
Net::SNMP


collected snmp data are like the following

 1.3.6.1.2.1.47.1.1.1.1.13.1 = "CISCO7609"
 1.3.6.1.2.1.47.1.1.1.1.13.14 = "FAN-MOD-09"
 1.3.6.1.2.1.47.1.1.1.1.13.17 = "FAN-MOD-09"
 1.3.6.1.2.1.47.1.1.1.1.13.20 = "WS-CAC-4000W-INT"
 1.3.6.1.2.1.47.1.1.1.1.13.29 = "WS-CAC-4000W-INT"
 1.3.6.1.2.1.47.1.1.1.1.13.40 = "WS-C6K-VTT" 

 $entPhysicalModelName (1.3.6.1.2.1.47.1.1.1.1.13) becomes a hash

 i.e.
 $entPhysicalModelName{'1'} = 'CISCO7609'
 $entPhysicalModelName{'14'} = 'FAN-MOD-09'


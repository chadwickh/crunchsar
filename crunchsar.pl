#!/usr/bin/perl
#
# crunchsar.pl - takes the output from sar -A, and creates .csv files to make
#                importation and graphing in excel easier.
#
#
# 20110322 - Still fighting through the exclusions/inclusions on disk data
#            Specifically changed so that anything that includes ".t" is excluded (as opposed to .t[0-9])
#            as well as removing ohci and md devices
# 20110124 - Changed date so that if it's only 2 digits (<100) we add 2000 to it
#            Thanks to Solaris 8!
# 20110120 - Renamed to crunchsar to make globing easier
# 20110119 - Changed to gather hostname, kernel release, architecture, and date from the first line
#            and to use the date to generate the time stamp, allowing for the case where sar data 
#            doesn't start at midnight - Thanks, customer!
#            Basically turned into a complete rewrite (or refactor as the cool kids call it)
# 20110111 - Changed to take a list of files to process
# 20100407 - Changed to take a single argument, the filename to process
#
# 20040610 - Changed Headers to exclude the leading time.  This caused an issue
#            where the time wasn't exactly 00:00:01.  Also changed so that any
#            line that begins with 00:00 is looked at to see if it's a header, and
#            changed the header matching so that it matches the end of the line.
#
#            Finally, changed the DISK_HEADER to only be qq{blks/s  avwait  avserv}
#            Not sure why but couldn't get a match otherwise
#
print qq{This is crunchsar.pl - Version 20110119\n};
# use statements
use Switch;
use Date::Calc qw(Add_Delta_Days);
# Constants (_hopefully_)
# DEBUG options
#    0 - no debugging output
#    1 - minimal
#    8 - show every line as it's processed
#    Options are additive, so anything > than 1 will show both
$DEBUG=0;
$oneday=1;
# This corresponds to sar -u
$HEADERS{CPU_HEADER}=qq{%usr    %sys    %wio   %idle};
# 
# This corresponds to sar -d
#$HEADERS{DISK_HEADER}=qq{device        %busy   avque   r+w/s  blks/s  avwait  avserv};
$HEADERS{DISK_HEADER}=qq{blks/s  avwait  avserv};
#
# This corresponds to sar -q
$HEADERS{QUEUE_HEADER}=qq{runq-sz %runocc swpq-sz %swpocc};
#
# This corresponds to sar -b
$HEADERS{BUFFER_HEADER}=qq{bread/s lread/s %rcache bwrit/s lwrit/s %wcache pread/s pwrit/s};
#
# This corresponds to sar -w
$HEADERS{SWAP_HEADER}=qq{swpin/s bswin/s swpot/s bswot/s pswch/s};
#
# This corresponds to sar -c
$HEADERS{SYSCALL_HEADER}=qq{scall/s sread/s swrit/s  fork/s  exec/s rchar/s wchar/s};
#
# This corresponds to sar -a
$HEADERS{FS_HEADER}=qq{iget/s namei/s dirbk/s};
#
# This corresponds to sar -y
$HEADERS{TTY_HEADER}=qq{rawch/s canch/s outch/s rcvin/s xmtin/s mdmin/s};
#
# This corresponds to sar -v
$HEADERS{PROC_HEADER}=qq{proc-sz    ov  inod-sz    ov  file-sz    ov   lock-sz};
#
# This corresponds to sar -m
$HEADERS{SEMA_HEADER}=qq{msg/s  sema/s};
#	
# This corresponds to sar -p
$HEADERS{PAGE_HEADER}=qq{atch/s  pgin/s ppgin/s  pflt/s  vflt/s slock/s};
#
# This corresponds to sar -g
$HEADERS{PAGE2_HEADER}=qq{pgout/s ppgout/s pgfree/s pgscan/s %ufs_ipf};
#
# This corresponds to sar -r
$HEADERS{MEM_HEADER}=qq{freemem freeswap};
#
# This corresponds to sar -k
$HEADERS{KMA_HEADER}=qq{sml_mem   alloc  fail  lg_mem   alloc  fail  ovsz_alloc  fail};
#
# Unconscionable hack to skip over averages
$HEADERS{AVERAGE}=qq{Average};
#
if ($DEBUG >0) {
   foreach $key (sort (keys(%HEADERS))) {
      print qq{$key: $HEADERS{"$key"}\n};
   }
}
#
if ($#ARGV < 0) {
	print qq{Usage:  crunchsar.pl <filename> [<filename2> ...]\n};
	print qq{\tWhere <filename> is the output from sar -A on a Solaris host\n};
	print qq{\n};
	exit 1;
}
#
foreach $input (@ARGV) {
	#
	open (INPUT, $input) || die qq{Could not open input file, $input};
	#
	#
	while (<INPUT>) {
	   chomp;
	   $line =$_;
	   $line =~ s/^\s+//;
       if( $line =~ /^SunOS/) {
          ($OS, $hostname, $osver, $kernel_patch, $arch, $date) = split;
          ($month, $day, $year) = split ('/', $date);
          if ($year < 100) {
          	$year+=2000;
          }
          # we need these to roll back if the output spans a day...
          $saved_month = $month;
          $saved_day = $day;
          $saved_year = $year;
          print qq{Processing file $input for host $hostname, date $date, month $month, day $day, year $year\n};
       }
	   if ($DEBUG > 7) {print qq{Processing: $line\n}};
	   $ISHEADER=0;
	   # This regular expression matches lines that begin with timestamps, "sd", or "ssd"
	   # this means that tape drives and nfs mounts are excluded as is anything else (be warned)
	   if ( ($line =~ /^[0-2][0-9]/) || ($line =~ /^sd/) || ($line =~ /^ssd/) || ($line =~ /^Average/)) {
	   # Gotta check every line with a timestamp to see if it's a header *sigh*
	      if (($line =~ /^[0-2][0-9]/) || ($line =~/^Average/)) {
	      	 ($hhmm, $rest) = split /\s+/, $line;
	      	 # Check to see if we've rolled over to a new day - if so use the Add_Delta_DHMS function from the DateCalc module to add
	      	 # a day.
	      	 if (!(defined $saved_hhmm)) {
	      	 	$saved_hhmm = $hhmm;
	      	 }
	      	 if ($hhmm < $saved_hhmm) {
	      	 	($year, $month, $day) = Add_Delta_Days ( $year, $month, $day, $oneday);
	         }
	         $saved_hhmm = $hhmm;
	         # We use the YYYY/MM/DD format for dates to make sorting easier/work...
	         $time=qq{$year/$month/$day $hhmm};
	         if ($DEBUG > 0)  {print qq{Using timestamp $time\n}};
	         # Trying to eliminate as much extra work as necessary - we need the above to create the timestamps, but
	         # let's only look for a header if there's text or a percent sign after the time stamp.
	         # We exclude nfs here, too
	         if ((($line =~ /^[0-2][0-9]:[0-5][0-9]:[0-5][0-9]\s+[a-zA-Z%]/) || ($line =~ /^Average/))&& !($line =~ /^[0-2][0-9]:[0-5][0-9]:[0-5][0-9]\s+nfs/)) {
	         	if ($DEBUG > 0) {print qq{Checking $line to see if it's a header\n}};
	         	foreach $key (sort (keys (%HEADERS))) {
	            	if ($DEBUG > 0 ) {print qq{Checking $HEADERS{"$key"} against $line\n}};
	            	if ($line =~ /$HEADERS{"$key"}/) {
	               		print qq{Processing $key\n};
	               		$SECTION=$key;
	               		$ISHEADER=1;
	               		# reset the date
	               		$year=$saved_year;
	               		$month=$saved_month;
	               		$day=$saved_day;
	               		last;
	            	}
	         	}
	         }
	      }
	      if ($DEBUG > 7) {print qq{ISHEADER: $ISHEADER\n};};
	      if (!$ISHEADER) {
	      	 if ($DEBUG > 7) {print qq{Now processing: $line\n};};
	         switch ($SECTION) {
	            case qq{CPU_HEADER}      {if ($DEBUG > 0 ) {print qq{Found $SECTION\n}};
	                                         ($ignore, $usr, $sys, $wio, $idle) = split /\s+/,$line;
	                                         $cpu_usr{"$time"}=$usr;
	                                         $cpu_sys{"$time"}=$sys;
	                                         $cpu_wio{"$time"}=$wio;
	                                         $cpu_idle{"$time"}=$idle;
	                                     }
	            case qq{DISK_HEADER}     {#if ($DEBUG > 0 ) {print qq{Found $SECTION\n}};
	                                      # We have to accomodate two possible formats here - one where the timestamp is at the start of the line
	                                      # and a second where we start off with the device name
	                                      if ($line =~ /^[0-2][0-9]/) {
	                                         ($ignore, $device, $busy, $avque, $ios, $blocks, $avwait, $avserv) = split /\s+/,$line;
					                      } else {
	                                         ($device, $busy, $avque, $ios, $blocks, $avwait, $avserv) = split /\s+/,$line; 
	                                      }
	                                      # And this will exclude statistics about slices and mpxio paths
	                                      if (! (($device =~ /\,/) || ($device =~ /\.t/) || ($device =~/^md/) || ($device =~/^ohci/))) {
	                                         $disk_busy{$device}{"$time"} = $busy;
	                                         $disk_avque{$device}{"$time"} = $avque;
	                                         $disk_ios{$device}{"$time"} = $ios;
	                                         $disk_blocks{$device}{"$time"} = $blocks;
	                                         $disk_avwait{$device}{"$time"} = $avwait;
	                                         $disk_avserv{$device}{"$time"} = $avserv;
                                             $aggr_blocks{"$time"} += $blocks;
                                             $aggr_ios{"$time"} += $ios;
                                             if ($DEBUG > 7) {print qq{Using: $time, $device, $busy, $avque, $ios, $blocks, $avwait, $avserv, $aggr_blocks{"$time"}, $aggr_ios{"$time"}\n}};
	                                        } 
	                                     }
	            case qq{QUEUE_HEADER}    {if ($DEBUG > 0 ) {print qq{Found $SECTION\n}};($time, $qsize, $qocc, $swpqsize, $swpqocc) = split /\s+/,$line;}
	            case qq{BUFFER_HEADER}   {if ($DEBUG > 0 ) {print qq{Found $SECTION\n}};($time, $bread, $lread, $rcache, $bwrit, $lwrit, $wcache, $pread, $pwrit) = split /\s+/,$line;}
	            case qq{SWAP_HEADER}     {if ($DEBUG > 0 ) {print qq{Found $SECTION\n}};($time, $swpin, $bwin, $swpot, $bswot, $pswch) = split /\s+/,$line;}
	            case qq{SYSCALL_HEADER}  {if ($DEBUG > 0 ) {print qq{Found $SECTION\n}};($time, $scall, $sread, $swrit, $fork, $exec, $rcahr, $wchar) = split /\s+/,$line;}
	            case qq{FS_HEADER}       {if ($DEBUG > 0 ) {print qq{Found $SECTION\n}};($time, $iget, $namei, $dirbk) = split /\s+/,$line;}
	            case qq{TTY_HEADER}      {if ($DEBUG > 0 ) {print qq{Found $SECTION\n}};($time, $rawch, $canch, $outch, $rcvin, $xmtin, $mdmin) = split /\s+/,$line;}
	            case qq{PROC_HEADER}     {if ($DEBUG > 0 ) {print qq{Found $SECTION\n}};($time, $procsz, $ov, $inodsz, $ov2, $filesz, $ov3, $locksz) = split /\s+/,$line;}
	            case qq{SEMA_HEADER}     {if ($DEBUG > 0 ) {print qq{Found $SECTION\n}};($time, $msg, $sema) = split /\s+/,$line;}
	            case qq{PAGE_HEADER}     {if ($DEBUG > 0 ) {print qq{Found $SECTION\n}};($time, $atch, $pgin, $ppgin, $pflt, $vflt, $slock) = split /\s+/,$line;}
	            case qq{PAGE2_HEADER}    {if ($DEBUG > 0 ) {print qq{Found $SECTION\n}};($time, $pgout, $ppgout, $pgfree, $pgscan, $ufs_ipf) = split /\s+/,$line;}
	            case qq{MEM_HEADER}      {if ($DEBUG > 0 ) {print qq{Found $SECTION\n}};
	            						  ($ignore, $freemem, $freeswap) = split /\s+/,$line;
	                                      $freemem{"$time"}=$freemem;
	                                      $freeswap{"$time"}=$freeswap;   
	                                     }
	            case qq{KMA_HEADER}      {if ($DEBUG > 0 ) {print qq{Found $SECTION\n}};($ignore, $sml_mem, $alloc, $fail, $lg_mem, $alloc, $fail, $ovsz_alloc, $fail) = split /\s+/,$line;}
	            case qq{AVERAGE}		 {if ($DEBUG > 0 ) {print qq{Found $SECTION\n}}; }
	            else                     {print qq{Could not match $SECTION to any of the predefined headers!!!\n};}
	         }
	      }
	   }
	}
	close INPUT;
}
#
# Done processing file, now do something useful with the output...
print qq{Generating CPU Utilization Report\n};
open (CPU, qq{>./cpu.$hostname.csv}) || die qq{Cannot create file for CPU Utilization report!\n};
print CPU qq{Time, User, System, WIO, Idle\n};
foreach $key (sort (keys(%cpu_usr))) {
   print CPU qq{$key, $cpu_usr{"$key"}, $cpu_sys{"$key"}, $cpu_wio{"$key"}, $cpu_idle{"$key"}\n};
}
#
#
print qq{Generating Memory Utilization Report\n};
open (MEM, qq{>./mem.$hostname.csv}) || die qq{Cannot create file for Memory Utilization report!\n};
print MEM qq{Time, Freemem, Freeswap\n};
foreach $time (sort (keys(%freemem))) {
   print MEM qq{$time, $freemem{"$time"}, $freeswap{"$time"}\n};
}
#
#
print qq{Generating disk %busy report\n};
open (DISKBUSY, qq{>./diskbusy.$hostname.csv}) || die qq{Cannot create file for Disk %busy report!\n};
# print out the header with the times - relies on the fact that all of these data series have the same times
foreach $time (sort (keys(%cpu_usr))) {
	print DISKBUSY qq{,$time};
}
print DISKBUSY qq{\n};
foreach $dev (sort (keys(%disk_busy))) {
   print DISKBUSY qq{$dev};
   foreach $time (sort (keys (%{$disk_busy{$dev}}))) {
      print DISKBUSY qq{, $disk_busy{$dev}{"$time"}};
   }
   print DISKBUSY qq{\n};
}
#
#
print qq{Generating disk avwait report\n};
open (DISKAVWAIT, qq{>./diskavwait.$hostname.csv}) || die qq{Cannot create file for Disk avwait report!\n};
# print out the header with the times - relies on the fact that all of these data series have the same times
foreach $time (sort (keys(%cpu_usr))) {
	print DISKAVWAIT qq{,$time};
}
print DISKAVWAIT qq{\n};
foreach $dev (sort (keys(%disk_avwait))) {
   print DISKAVWAIT qq{$dev};
   foreach $time (sort (keys (%{$disk_avwait{$dev}}))) {
      print DISKAVWAIT qq{, $disk_avwait{$dev}{"$time"}};
   }
   print DISKAVWAIT qq{\n};
}
#
#
print qq{Generating disk avserv report\n};
open (DISKAVSERV, qq{>./diskavserv.$hostname.csv}) || die qq{Cannot create file for Disk avserv report!\n};
# print out the header with the times - relies on the fact that all of these data series have the same times
foreach $time (sort (keys(%cpu_usr))) {
	print DISKAVSERV qq{,$time};
}
print DISKAVSERV qq{\n};

foreach $dev (sort (keys(%disk_avserv))) {
   print DISKAVSERV qq{$dev};
   foreach $time (sort (keys (%{$disk_avserv{$dev}}))) {
      print DISKAVSERV qq{, $disk_avserv{$dev}{"$time"}};
   }
   print DISKAVSERV qq{\n};
}
#
#
print qq{Generating Aggregate blocks/s report\n};
open (AGGRBLOCKS, qq{>./aggrblocks.$hostname.csv}) || die qq{Cannot create file for Aggregate blocks/s report\n};
foreach $time (sort (keys (%aggr_blocks))) {
   print AGGRBLOCKS qq{$time, $aggr_blocks{"$time"}\n};
}
#
#
print qq{Generating Aggregate iops report\n};
open (AGGRIOPS, qq{>./aggriops.$hostname.csv}) || die qq{Cannot create file for Aggregate iops report\n};
foreach $time (sort (keys (%aggr_ios))) {
   print AGGRIOPS qq{$time, $aggr_ios{"$time"}\n};
}

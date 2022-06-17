
$ComputerFQDN= $env:COMPUTERNAME+"."+ $env:USERDNSDOMAIN
$logfilepath="$env:windir\logs\$ComputerFQDN" + ".log"

$searchCriteria="DeploymentAction=* AND Type='Software'and IsInstalled=0"

$CurrentDatetime=Get-Date

$UpdateTitles=@("2022-06 Cumulative Update for Windows 11 for x64-based Systems (KB5014668)","Title2")

function Write-Log 
{ 
    [CmdletBinding()] 
    Param 
    ( 
        [Parameter(Mandatory=$true, 
                   ValueFromPipelineByPropertyName=$true)] 
        [ValidateNotNullOrEmpty()] 
        [Alias("LogContent")] 
        [string]$Message, 
 
        [Parameter(Mandatory=$false)] 
        [Alias('LogPath')] 
        [string]$Path=$logfilepath, 
         
        [Parameter(Mandatory=$false)] 
        [ValidateSet("Error","Warn","Info")] 
        [string]$Level="Info", 
         
        [Parameter(Mandatory=$false)] 
        [switch]$NoClobber 
    ) 
 
    Begin 
    { 
        # Set VerbosePreference to Continue so that verbose messages are displayed. 
        $VerbosePreference = 'Continue' 
    } 
    Process 
    { 
         
        # If the file already exists and NoClobber was specified, do not write to the log. 
        if ((Test-Path $Path) -AND $NoClobber)
		   { 
            Write-Error "Log file $Path already exists, and you specified NoClobber. Either delete the file or specify a different name." 
            Return 
            } 
 
        # If attempting to write to a log file in a folder/path that doesn't exist create the file including the path. 
        elseif (!(Test-Path $Path))
			{ 
            Write-Verbose "Creating $Path." 
            $NewLogFile = New-Item $Path -Force -ItemType File 
            } 
 
        else { 
            # Nothing to see here yet. 
            } 
 
        # Format Date for our Log File 
        $FormattedDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss" 
 
        # Write message to error, warning, or verbose pipeline and specify $LevelText 
        switch ($Level) { 
            'Error' { 
                Write-Error $Message 
                $LevelText = 'ERROR:' 
                } 
            'Warn' { 
                Write-Warning $Message 
                $LevelText = 'WARNING:' 
                } 
            'Info' { 
                Write-Verbose $Message 
                $LevelText = 'INFO:' 
                } 
            } 
         
        # Write log entry to $Path 
        "$FormattedDate $LevelText $Message" | Out-File -FilePath $Path -Append 
    }

    End 

    { 

    } 
} # END FUNCTION ENABLE LOGGING

Write-Log -Message "******************Starting Patch Install Script Current time is $CurrentDatetime******************" -Level Info


#Create Objects needed for Scan and update Installs
$UpdateSession = New-Object -ComObject Microsoft.Update.Session
$UpdateSearcher = $UpdateSession.CreateupdateSearcher()
$UpdateSvc = New-Object -ComObject Microsoft.Update.ServiceManager 

#check if the ONline Catalog service Exists If not Add it

Write-Log "Checking if Online Scan service is registered...."
$onlineexists=$false

if(($updatesvc.QueryServiceRegistration('7971f918-a847-4430-9279-4a52d1efe18d').service) -eq $null)

{Write-Log "Service doesnt exist will add it"
     Try
         { Write-Log "Registering Online Scan Service with ID '7971f918-a847-4430-9279-4a52d1efe18d'" 
           $UpdateSvc.AddService2("7971f918-a847-4430-9279-4a52d1efe18d",'7',"")
          }

          Catch{ Write-Log "Failed to register service will have to quit"}
    
  
  
}
 Else { Write-log "Service for online scan exists, will proceed with Scan" }
 
    
#Switch this to 2 for online and 1 for Default(Usually WSUS on SCCM client)
$UpdateSearcher.ServerSelection=2
$updateSearcher.ServiceID ='7971f918-a847-4430-9279-4a52d1efe18d'

#Search for updates

Write-Log "Searching for updates....."

try{
$updates=$UpdateSearcher.Search($searchCriteria)
}

catch {Write-Log "Failed to scan updates with error $_.Exception.Message "
Exit
}
#create update COllection
#

$UpdatestoInstall= New-Object -ComObject microsoft.update.updatecoll
$UpdatestoInstall.Clear()



########################END get updates from Azure Tables

 $filterstring=$UpdateTitles

 Write-Log "Filtering the updates Current criteria is  $filterstring"



foreach($update in $updates.Updates)


{ if (($($update.title) -in $filterstring) -and ($($update.IsInstalled) -ne 'True'))

    {  
       Write-Log "found update matching criteria will add to the downloadand install collection...  $($update.Title)"

        $UpdatestoInstall.add($update)
    }

}


if($UpdatestoInstall -ne "")
{   write-log "Starting download for updates current batch has $($updatestoinstall.count) Updates"
     Write-Log "updates to install are $(($UpdatestoInstall|select title).title)"

      Try{
            #download updates

            $downloader = $UpdateSession.CreateUpdateDownloader() 
            $downloader.Updates=$UpdatestoInstall
            $downloader.Download()

            Write-log "Update downloaded succesfully" 

         }

     Catch
       { Write-log "Download of the update Failed $_.Exception.Message" 
       }#endtrycatch

  
}#endIfloop

Else
{Write-log "No applicable updates Found Ending Install Rutine" 
exit
}#endElse

$lastupdateinstalled=''
$lastupdateinstalldate=''
$lastinstallstatus=''

Write-log "Installing Updates....." 

Try
{
     $Installer = $UpdateSession.CreateUpdateInstaller()

    $Installer.Updates = $UpdatestoInstall
    $Results = $Installer.Install()


    }
    Catch
    {  write-log "Install failed $_.Exception.Message"  }

    $lastupdateinstalled=''

    if ($Results.HResult -ne 0)

    { $lastinstallstatus='Install Failed'
      
     #scan for history top 10

     $history=$UpdateSearcher.QueryHistory(0,10)
     $out=$history |where {(($_.Title -like "*cumulative update for windows*") -or($_.Title -like "*Servicing Stack update for windows*"))-and ($_.HResult -eq 0)}|Sort-Object -Property Date -Descending

     Foreach($uupdate in $out)
      {
     $lastupdateinstalled+= "\" +$uupdate.Title
     $lastupdateinstalldate+= "\" + $uupdate.Date
     }
     #Sort-Object -Descending -Property Date|
    }

    Else

    { Write-Log "Installation was successfull" 
    
       $lastinstallstatus='Install Success'
      foreach($content in $UpdatestoInstall)
       {
      
         if(($content.Title -like "*Cumulative*") -or ($content.Title -like "*Servicing Stack*"))
             {
                $lastupdateinstalled+= "\" + $content.Title
                 $lastupdateinstalldate=$CurrentDatetime
        }
        }
    }

    
    

    

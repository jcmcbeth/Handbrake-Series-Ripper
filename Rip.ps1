param(
    [string]$Source = ((Get-CimInstance Win32_LogicalDisk | ?{ $_.DriveType -eq 5 } | Select-Object DeviceID -First 1).DeviceID),
    [string]$DefinitionFileName = (Join-Path (Get-Location) "rip.json"),
    [string]$DestinationPath = (Get-Location),
    [string]$HandbrakePath = $env:HandbrakeCliPath
)

#Write-Output $Source;
#Write-Output $DefinitionFileName;
#Write-Output $DestinationPath;
#Write-Output $env:HandbrakeCliPath

# Without the encoding, Pokémon and such is messed up.
$media = Get-Content -Raw -Path $DefinitionFileName -Encoding UTF8 | ConvertFrom-Json;
$diskName = Get-CimInstance Win32_LogicalDisk | ?{ $_.DeviceID -eq $Source } | Select-Object -ExpandProperty VolumeName;

# TODO Verify this shows error when no disk drive
if ($diskName -eq "" -or $diskName -eq $null) {
    throw "Did not found source disk '$Source'.";
}

$disc = $media.discs | Where { $_.name -eq $diskName };

if ($disc -eq $null) {
    throw "Did not find '$diskName' on source '$Source'.";
}

if ([System.String]::IsNullOrWhiteSpace($HandbrakePath)) {
    throw "Handbrake path was not set.";
}

if ((Test-Path $HandbrakePath) -eq $false) {
    throw "Handbrake was not found at '$HandbrakePath'.";
}

$episodeNumber = 1;
$activity = "Ripping DVD";
foreach ($episode in $disc.episodes) {
    $childActivity = "$($media.title) - S$($episode.season.ToString("00"))E$($episode.episode.ToString("00")) - $($episode.title)";
    
    $totalPercent = [int]((($episodeNumber - 1)/[double]$disc.episodes.Count) * 100);
    $episodeNumber = $episodeNumber + 1;

    Write-Progress -Id 1 -Activity $activity -PercentComplete $totalPercent;

    $fileName = "$($media.title) - S$($episode.season.ToString("00"))E$($episode.episode.ToString("00")) - $($episode.title) ($($episode.year)).mp4";
    $path = Join-Path $DestinationPath "\$($media.title)\Season $($episode.season.ToString("00"))\";

    if (-not (Test-Path $path)) {
        New-Item -ItemType Directory $path | Out-Null;
    }

    $path = Join-Path $path $fileName;

    #Write-Output "Path: $path";

    $arguments = "--input ""$Source"" --output ""$path"" --title $($episode.disc_title) --chapters $($episode.chapters) --format av_mp4 --optimize --preset ""HQ 480p30 Surround"" --markers --subtitle $($episode.subtitles)";
    #Write-Output "Arguments: $arguments";

    $process = New-Object System.Diagnostics.Process;
    $process.StartInfo.Filename = $HandbrakePath;
    $process.StartInfo.Arguments = $arguments;
    #$process.StartInfo.Arguments = "-h";
    $process.StartInfo.UseShellExecute = $false;
    $process.StartInfo.RedirectStandardOutput = $true;
    #$process.StartInfo.RedirectStandardError = $true;
    #$process.StartInfo.CreateNoWindow = $true;
    $process.Start() | Out-Null;
    while (($line = $process.StandardOutput.ReadLine()) -ne $null)
    {
        [Regex]$regex = "(?<operation>.*?), (?<percent_complete>\d{1,3}\.\d{2}) %(?: \((?<fps>\d{1,3}\.\d{2}) fps, avg (?<average_fps>\d{1,3}\.\d{2}) fps, ETA (?<eta_hour>\d{2})h(?<eta_min>\d{2})m(?<eta_sec>\d{2})s\))?";

        # Encoding: task 1 of 2, 1.85 % (0.00 fps, avg 0.00 fps, ETA 00h06m00s)
        # Encoding: task 1 of 2, 0.83 % (0.00 fps, avg 0.00 fps, ETA 00h05m02s)
        $match = $regex.Match($line);

        if ($match.Success)
        {
            $childPercent = [int]$match.Groups["percent_complete"].Value;
            $operation = $match.Groups["operation"];

            #Write-Output "$($operation): $childPercent";

            if ($match.Groups["eta_sec"].Success)
            {
                $hour = [int]$match.Groups["eta_hour"].Value;
                $min = [int]$match.Groups["eta_min"].Value;
                $sec = [int]$match.Groups["eta_sec"].Value;

                $secondsRemaining = [int](New-TimeSpan -Hours $hour -Minutes $min -Seconds $sec).TotalSeconds;

                Write-Progress -ParentId 1 -Activity $childActivity -CurrentOperation $operation -PercentComplete $childPercent -SecondsRemaining $secondsRemaining;
            }
            else
            {
                Write-Progress -ParentId 1 -Activity $childActivity -CurrentOperation $operation -PercentComplete $childPercent;   
            }                   
        }
        else {
            Write-Output $line;
        }
    }
    $process.WaitForExit();
    Write-Progress -Activity $childActivity -Completed;

    #.\HandBrakeCLI.exe --input $Source --output $path --title $episode.titles --chapters $episode.chapter --format "av_mp4" --optimize --preset "Fast 480p30" --markers --subtitle $episode.subtitles
}

Write-Progress -Activity $activity -Id 1 -Completed;


# .\HandBrakeCLI.exe --input "E:" --output "Family Guy - S03E17 - Brian Wallows and Peter's Swallows (2002).mp4" --title 1 --chapters 1-5 --format "av_mp4" --optimize --preset "Fast 480p30" --markers --subtitle 5
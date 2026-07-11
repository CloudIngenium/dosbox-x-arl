param(
    [string]$RunPath = "",

    [string]$CapturePath = "",

    [string]$RunRoot = "C:\ARL\diagnostics",

    [string[]]$PrinterName = @("EPSON LX-350"),

    [ValidateSet("Raw", "Text", "Formatted")]
    [string]$PrintMode = "Raw",

    [string]$CaptureName = "LPTCAP.PRN",

    [switch]$LatestPrintJob,

    [switch]$AppendFormFeed,

    [switch]$Send
)

$ErrorActionPreference = "Stop"

if (-not [string]::IsNullOrWhiteSpace($CapturePath)) {
    if (-not (Test-Path -Path $CapturePath -PathType Leaf)) {
        throw "Capture file not found: $CapturePath"
    }
} elseif ([string]::IsNullOrWhiteSpace($RunPath)) {
    $candidate = Get-ChildItem -Path $RunRoot -Directory |
        Where-Object { Test-Path -Path (Join-Path $_.FullName $CaptureName) -PathType Leaf } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($null -eq $candidate) {
        throw "No run with $CaptureName found below $RunRoot"
    }

    $RunPath = $candidate.FullName
}

if ([string]::IsNullOrWhiteSpace($CapturePath)) {
    if (-not (Test-Path -Path $RunPath -PathType Container)) {
        throw "Run path not found: $RunPath"
    }

    if ($LatestPrintJob) {
        $printJobsPath = Join-Path $RunPath "print-jobs"
        $latestJob = Get-ChildItem -Path $printJobsPath -Filter "*.prn" -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if ($null -eq $latestJob) {
            throw "No finalized print job found below $printJobsPath"
        }
        $CapturePath = $latestJob.FullName
    } else {
        $CapturePath = Join-Path $RunPath $CaptureName
    }
    if (-not (Test-Path -Path $CapturePath -PathType Leaf)) {
        throw "Capture file not found: $CapturePath"
    }
}

$printers = @()
foreach ($name in $PrinterName) {
    $printer = Get-Printer -Name $name -ErrorAction SilentlyContinue
    if ($null -eq $printer) {
        $known = (Get-Printer | Select-Object -ExpandProperty Name) -join ", "
        throw "Printer '$name' not found. Known printers: $known"
    }
    $printers += $printer
}

$capture = Get-Item -Path $CapturePath
$previewBytes = [System.IO.File]::ReadAllBytes($capture.FullName)
$printBytes = $previewBytes
if ($AppendFormFeed -and ($printBytes.Length -eq 0 -or $printBytes[$printBytes.Length - 1] -ne 12)) {
    $withFormFeed = New-Object byte[] ($printBytes.Length + 1)
    if ($printBytes.Length -gt 0) {
        [Array]::Copy($printBytes, $withFormFeed, $printBytes.Length)
    }
    $withFormFeed[$withFormFeed.Length - 1] = 12
    $printBytes = $withFormFeed
}
$previewLength = [Math]::Min(300, $previewBytes.Length)
$preview = ""
if ($previewLength -gt 0) {
    $preview = -join ($previewBytes[0..($previewLength - 1)] | ForEach-Object {
        if ($_ -ge 32 -and $_ -le 126) { [char]$_ }
        elseif ($_ -eq 13) { "\r" }
        elseif ($_ -eq 10) { "\n" }
        elseif ($_ -eq 12) { "<FF>" }
        elseif ($_ -eq 27) { "<ESC>" }
        else { "." }
    })
}

Write-Host "Capture: $($capture.FullName)"
Write-Host "Bytes: $($capture.Length)"
Write-Host "Print mode: $PrintMode"
foreach ($printer in $printers) {
    Write-Host "Printer: $($printer.Name) on $($printer.PortName)"
}
if ($AppendFormFeed -and $printBytes.Length -ne $previewBytes.Length) {
    Write-Host "Print bytes: $($printBytes.Length) (appended form feed)"
}
Write-Host "Preview:"
Write-Host $preview

if (-not $Send) {
    Write-Host ""
    Write-Host "Dry run only. Re-run with -Send to print."
    exit 0
}

$source = @"
using System;
using System.Runtime.InteropServices;

public class ArlRawPrinter {
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Ansi)]
    public class DOCINFOA {
        [MarshalAs(UnmanagedType.LPStr)]
        public string pDocName;
        [MarshalAs(UnmanagedType.LPStr)]
        public string pOutputFile;
        [MarshalAs(UnmanagedType.LPStr)]
        public string pDataType;
    }

    [DllImport("winspool.Drv", EntryPoint="OpenPrinterA", SetLastError=true, CharSet=CharSet.Ansi, ExactSpelling=true)]
    public static extern bool OpenPrinter(string szPrinter, out IntPtr hPrinter, IntPtr pd);

    [DllImport("winspool.Drv", EntryPoint="ClosePrinter", SetLastError=true, ExactSpelling=true)]
    public static extern bool ClosePrinter(IntPtr hPrinter);

    [DllImport("winspool.Drv", EntryPoint="StartDocPrinterA", SetLastError=true, CharSet=CharSet.Ansi, ExactSpelling=true)]
    public static extern bool StartDocPrinter(IntPtr hPrinter, int level, [In] DOCINFOA di);

    [DllImport("winspool.Drv", EntryPoint="EndDocPrinter", SetLastError=true, ExactSpelling=true)]
    public static extern bool EndDocPrinter(IntPtr hPrinter);

    [DllImport("winspool.Drv", EntryPoint="StartPagePrinter", SetLastError=true, ExactSpelling=true)]
    public static extern bool StartPagePrinter(IntPtr hPrinter);

    [DllImport("winspool.Drv", EntryPoint="EndPagePrinter", SetLastError=true, ExactSpelling=true)]
    public static extern bool EndPagePrinter(IntPtr hPrinter);

    [DllImport("winspool.Drv", EntryPoint="WritePrinter", SetLastError=true, ExactSpelling=true)]
    public static extern bool WritePrinter(IntPtr hPrinter, byte[] pBytes, int dwCount, out int dwWritten);

    public static void SendBytes(string printerName, string documentName, byte[] bytes) {
        IntPtr hPrinter;
        if (!OpenPrinter(printerName, out hPrinter, IntPtr.Zero)) {
            throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "OpenPrinter failed");
        }

        try {
            DOCINFOA di = new DOCINFOA();
            di.pDocName = documentName;
            di.pDataType = "RAW";

            if (!StartDocPrinter(hPrinter, 1, di)) {
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "StartDocPrinter failed");
            }

            try {
                if (!StartPagePrinter(hPrinter)) {
                    throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "StartPagePrinter failed");
                }

                try {
                    int written;
                    if (!WritePrinter(hPrinter, bytes, bytes.Length, out written)) {
                        throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "WritePrinter failed");
                    }
                    if (written != bytes.Length) {
                        throw new Exception("WritePrinter wrote " + written + " of " + bytes.Length + " bytes");
                    }
                } finally {
                    EndPagePrinter(hPrinter);
                }
            } finally {
                EndDocPrinter(hPrinter);
            }
        } finally {
            ClosePrinter(hPrinter);
        }
    }
}
"@

if (-not ([System.Management.Automation.PSTypeName]"ArlRawPrinter").Type) {
    Add-Type -TypeDefinition $source
}

function ConvertTo-ArlPrintableText([byte[]]$Bytes) {
    $text = [System.Text.Encoding]::ASCII.GetString($Bytes)
    $text = $text -replace "`e\[[0-9;?]*[A-Za-z]", ""
    $text = $text -replace "`e.", ""
    $text = $text -replace "`f", "`r`n`r`n"
    return $text
}

function Send-ArlFormattedText {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $true)]
        [string]$TargetPrinter
    )

    Add-Type -AssemblyName System.Drawing

    $normalized = $Text -replace "`r`n", "`n" -replace "`r", "`n"
    $lines = @($normalized -split "`n")
    while ($lines.Count -gt 1 -and [string]::IsNullOrWhiteSpace($lines[$lines.Count - 1])) {
        $lines = @($lines[0..($lines.Count - 2)])
    }

    $document = New-Object System.Drawing.Printing.PrintDocument
    $document.PrinterSettings.PrinterName = $TargetPrinter
    if (-not $document.PrinterSettings.IsValid) {
        $document.Dispose()
        throw "Printer '$TargetPrinter' is not valid for formatted printing."
    }

    $document.DocumentName = "ARL IMPACT+ formatted report"
    $document.DefaultPageSettings.Landscape = $true
    $document.DefaultPageSettings.Margins = New-Object System.Drawing.Printing.Margins(25, 25, 25, 25)

    $state = @{
        Lines = $lines
        Index = 0
        Font = $null
    }

    $handler = [System.Drawing.Printing.PrintPageEventHandler]{
        param($sender, $eventArgs)

        if ($null -eq $state.Font) {
            $maxCharacters = [Math]::Max(1, ($state.Lines | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum)
            $lineCount = [Math]::Max(1, $state.Lines.Count)
            $widthPoints = $eventArgs.MarginBounds.Width * 72.0 / 100.0
            $heightPoints = $eventArgs.MarginBounds.Height * 72.0 / 100.0
            $sizeByWidth = $widthPoints / ($maxCharacters * 0.62)
            $sizeByHeight = $heightPoints / ($lineCount * 1.28)
            $fontSize = [Math]::Max(8.0, [Math]::Min(18.0, [Math]::Min($sizeByWidth, $sizeByHeight)))
            $state.Font = New-Object System.Drawing.Font("Courier New", [single]$fontSize, [System.Drawing.FontStyle]::Regular)
        }

        $lineHeight = $state.Font.GetHeight($eventArgs.Graphics)
        $linesPerPage = [Math]::Max(1, [Math]::Floor($eventArgs.MarginBounds.Height / $lineHeight))
        $y = [single]$eventArgs.MarginBounds.Top
        $printed = 0

        while ($state.Index -lt $state.Lines.Count -and $printed -lt $linesPerPage) {
            $eventArgs.Graphics.DrawString(
                $state.Lines[$state.Index],
                $state.Font,
                [System.Drawing.Brushes]::Black,
                [single]$eventArgs.MarginBounds.Left,
                $y
            )
            $state.Index++
            $printed++
            $y += $lineHeight
        }

        $eventArgs.HasMorePages = $state.Index -lt $state.Lines.Count
    }

    $document.add_PrintPage($handler)
    try {
        $document.Print()
    } finally {
        $document.remove_PrintPage($handler)
        if ($null -ne $state.Font) {
            $state.Font.Dispose()
        }
        $document.Dispose()
    }
}

function ConvertTo-ArlFormattedReport([string]$Text) {
    $finalIndex = $Text.LastIndexOf("Final Concentration", [System.StringComparison]::OrdinalIgnoreCase)
    if ($finalIndex -lt 0) {
        return $Text
    }

    $section = $Text.Substring($finalIndex) -replace "`r`n", "`n" -replace "`r", "`n"
    $lines = @($section -split "`n" | ForEach-Object { $_.TrimEnd() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($lines.Count -lt 7) {
        return $Text
    }

    $alloyLine = $lines | Where-Object { $_ -match '^ALLOY\s*:' } | Select-Object -First 1
    $sampleLine = $lines | Where-Object { $_ -match '^Sample\s+id\s*:' } | Select-Object -First 1
    $sampleIndex = [Array]::IndexOf($lines, $sampleLine)
    if ([string]::IsNullOrWhiteSpace($alloyLine) -or $sampleIndex -lt 0 -or $sampleIndex + 4 -ge $lines.Count) {
        return $Text
    }

    $namesA = @($lines[$sampleIndex + 1] -split '\s+' | Where-Object { $_ })
    $valuesA = @($lines[$sampleIndex + 2] -split '\s+' | Where-Object { $_ })
    $namesB = @($lines[$sampleIndex + 3] -split '\s+' | Where-Object { $_ })
    $valuesB = @($lines[$sampleIndex + 4] -split '\s+' | Where-Object { $_ })
    if ($namesA.Count -ne $valuesA.Count -or $namesB.Count -ne $valuesB.Count -or ($namesA.Count + $namesB.Count) -lt 10) {
        return $Text
    }

    $pairs = @()
    for ($index = 0; $index -lt $namesA.Count; $index++) {
        $pairs += [pscustomobject]@{ Name = $namesA[$index]; Value = $valuesA[$index] }
    }
    for ($index = 0; $index -lt $namesB.Count; $index++) {
        $pairs += [pscustomobject]@{ Name = $namesB[$index]; Value = $valuesB[$index] }
    }

    $output = New-Object System.Collections.Generic.List[string]
    $output.Add("ARL IMPACT+ - FINAL CONCENTRATION")
    $output.Add($alloyLine.Trim())
    $output.Add($sampleLine.Trim())
    $output.Add("")
    $columns = 5
    for ($start = 0; $start -lt $pairs.Count; $start += $columns) {
        $headers = New-Object System.Collections.Generic.List[string]
        $values = New-Object System.Collections.Generic.List[string]
        for ($column = 0; $column -lt $columns; $column++) {
            $pairIndex = $start + $column
            if ($pairIndex -lt $pairs.Count) {
                $headers.Add(('{0,-14}' -f $pairs[$pairIndex].Name))
                $values.Add(('{0,-14}' -f $pairs[$pairIndex].Value))
            }
        }
        $output.Add(($headers -join ""))
        $output.Add(($values -join ""))
        $output.Add("")
    }

    return $output -join "`r`n"
}

foreach ($printer in $printers) {
    if ($PrintMode -eq "Raw") {
        [ArlRawPrinter]::SendBytes($printer.Name, "ARL IMPACT+ LPT capture", $printBytes)
        Write-Host "Sent $($printBytes.Length) RAW bytes to $($printer.Name)."
    } elseif ($PrintMode -eq "Text") {
        $textPath = Join-Path ([System.IO.Path]::GetTempPath()) ("arl-lpt-{0}.txt" -f ([guid]::NewGuid().ToString("N")))
        try {
            ConvertTo-ArlPrintableText $previewBytes | Set-Content -Path $textPath -Encoding ASCII
            Get-Content -Path $textPath | Out-Printer -Name $printer.Name
            Write-Host "Sent text-rendered capture to $($printer.Name)."
        } finally {
            Remove-Item -Path $textPath -Force -ErrorAction SilentlyContinue
        }
    } else {
        $formattedText = ConvertTo-ArlPrintableText $previewBytes
        $formattedText = ConvertTo-ArlFormattedReport $formattedText
        Send-ArlFormattedText -Text $formattedText -TargetPrinter $printer.Name
        Write-Host "Sent auto-fitted formatted capture to $($printer.Name)."
    }
}

param(
    [string]$RunPath = "",

    [string]$CapturePath = "",

    [string]$RunRoot = "C:\ARL\diagnostics",

    [string]$PrinterName = "EPSON LX-350",

    [string]$CaptureName = "LPTCAP.PRN",

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

    $CapturePath = Join-Path $RunPath $CaptureName
    if (-not (Test-Path -Path $CapturePath -PathType Leaf)) {
        throw "Capture file not found: $CapturePath"
    }
}

$printer = Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue
if ($null -eq $printer) {
    $known = (Get-Printer | Select-Object -ExpandProperty Name) -join ", "
    throw "Printer '$PrinterName' not found. Known printers: $known"
}

$capture = Get-Item -Path $CapturePath
$previewBytes = [System.IO.File]::ReadAllBytes($capture.FullName)
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
Write-Host "Printer: $($printer.Name) on $($printer.PortName)"
Write-Host "Preview:"
Write-Host $preview

if (-not $Send) {
    Write-Host ""
    Write-Host "Dry run only. Re-run with -Send to send RAW bytes to the printer."
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

[ArlRawPrinter]::SendBytes($printer.Name, "ARL IMPACT+ LPT capture", $previewBytes)
Write-Host "Sent $($previewBytes.Length) RAW bytes to $($printer.Name)."

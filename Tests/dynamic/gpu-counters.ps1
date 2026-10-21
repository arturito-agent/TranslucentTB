# Test-only PDH reader. Dot-source once in a measurement process; always Dispose.
if (-not ('DynamicGpuCounters' -as [type])) {
Add-Type @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public sealed class DynamicGpuCounters : IDisposable {
    [StructLayout(LayoutKind.Sequential)] struct Value { public uint Status; public double Number; }
    [StructLayout(LayoutKind.Sequential)] struct Item { public IntPtr Name; public Value Data; }
    sealed class Counter { public string Kind; public IntPtr Handle; public uint StartupStatus; }
    public sealed class Sample {
        public string Kind,Instance;
        public uint Status;
        public double? Number;
    }
    [DllImport("pdh.dll",CharSet=CharSet.Unicode)] static extern uint PdhOpenQuery(string source,UIntPtr user,out IntPtr query);
    [DllImport("pdh.dll",CharSet=CharSet.Unicode)] static extern uint PdhAddEnglishCounter(IntPtr query,string path,UIntPtr user,out IntPtr counter);
    [DllImport("pdh.dll")] static extern uint PdhCollectQueryData(IntPtr query);
    [DllImport("pdh.dll",CharSet=CharSet.Unicode)] static extern uint PdhGetFormattedCounterArray(IntPtr counter,uint format,ref uint size,out uint count,IntPtr items);
    [DllImport("pdh.dll")] static extern uint PdhCloseQuery(IntPtr query);
    IntPtr query,buffer;
    uint capacity,openStatus;
    bool disposed;
    readonly List<Counter> counters=new List<Counter>();
    const uint MoreData=0x800007d2;
    const uint FormatDoubleNoCap=0x8200;

    public DynamicGpuCounters() {
        openStatus=PdhOpenQuery(null,UIntPtr.Zero,out query);
        if(openStatus!=0)return;
        Add("engine_percent",@"\GPU Engine(*)\Utilization Percentage");
        Add("dedicated_bytes",@"\GPU Process Memory(*)\Dedicated Usage");
        Add("shared_bytes",@"\GPU Process Memory(*)\Shared Usage");
    }
    void Add(string kind,string path) {
        IntPtr handle;
        uint status=PdhAddEnglishCounter(query,path,UIntPtr.Zero,out handle);
        counters.Add(new Counter {Kind=kind,Handle=handle,StartupStatus=status});
    }
    static Sample Error(string kind,uint status) {
        return new Sample {Kind=kind,Instance="",Status=status,Number=null};
    }
    public Sample[] Read() {
        if(disposed)throw new ObjectDisposedException("DynamicGpuCounters");
        var result=new List<Sample>();
        if(query==IntPtr.Zero) return new Sample[] {Error("query",openStatus)};
        uint collect=PdhCollectQueryData(query);
        if(collect!=0)return new Sample[] {Error("query",collect)};
        int itemSize=Marshal.SizeOf(typeof(Item));
        foreach(Counter counter in counters) {
            if(counter.StartupStatus!=0) { result.Add(Error(counter.Kind,counter.StartupStatus));continue; }
            uint size=capacity,count;
            uint status=PdhGetFormattedCounterArray(counter.Handle,FormatDoubleNoCap,ref size,out count,buffer);
            if(status==MoreData) {
                // Re-probe from zero: a too-small nonzero size is not reliable.
                size=0;
                status=PdhGetFormattedCounterArray(counter.Handle,FormatDoubleNoCap,ref size,out count,IntPtr.Zero);
                if(status==MoreData && size>0 && size<int.MaxValue-1024) {
                    uint replacementCapacity=size+1024;
                    IntPtr replacement=Marshal.AllocHGlobal((int)replacementCapacity);
                    if(buffer!=IntPtr.Zero)Marshal.FreeHGlobal(buffer);
                    buffer=replacement;capacity=replacementCapacity;
                    size=capacity;
                    status=PdhGetFormattedCounterArray(counter.Handle,FormatDoubleNoCap,ref size,out count,buffer);
                }
            }
            if(status!=0) { result.Add(Error(counter.Kind,status));continue; }
            if((ulong)count*(uint)itemSize>size) {result.Add(Error(counter.Kind,13));continue;}
            for(uint index=0;index<count;index++) {
                Item item=(Item)Marshal.PtrToStructure(IntPtr.Add(buffer,checked((int)index*itemSize)),typeof(Item));
                double? number=(item.Data.Status==0 || item.Data.Status==1) &&
                    !Double.IsNaN(item.Data.Number) && !Double.IsInfinity(item.Data.Number) ? (double?)item.Data.Number : null;
                result.Add(new Sample {Kind=counter.Kind,Instance=Marshal.PtrToStringUni(item.Name),Status=item.Data.Status,Number=number});
            }
        }
        return result.ToArray();
    }
    public void Dispose() {
        disposed=true;
        if(query!=IntPtr.Zero) {PdhCloseQuery(query);query=IntPtr.Zero;}
        if(buffer!=IntPtr.Zero) {Marshal.FreeHGlobal(buffer);buffer=IntPtr.Zero;capacity=0;}
    }
}
'@
}

function Write-DynamicGpuObservation($Reader, $Rows, [string] $Output, [string] $Label, [string] $Commit) {
    $scope = @{}
    foreach ($row in $Rows) { $scope[[string]$row.pid] = [ordered]@{pid=$row.pid;role=$row.role;process=$row.process} }
    $begin = [Diagnostics.Stopwatch]::GetTimestamp()
    $samples = @($Reader.Read())
    $end = [Diagnostics.Stopwatch]::GetTimestamp()
    $entries = @(foreach ($sample in $samples) {
        $match = [regex]::Match($sample.Instance, '^pid_([0-9]+)_')
        $owner = if($match.Success){$scope[$match.Groups[1].Value]}else{$null}
        # Keep provider errors, and only the process IDs already in the CPU scope.
        if ($owner -or -not $sample.Instance) {
            [ordered]@{kind=$sample.Kind;instance=$sample.Instance;status=$sample.Status;value=$sample.Number
                pid=$(if($owner){$owner.pid}else{$null});role=$(if($owner){$owner.role}else{$null})}
        }
    })
    $record = [ordered]@{label=$Label;commit=$Commit;qpc_begin=$begin;qpc_end=$end;qpc_frequency=[Diagnostics.Stopwatch]::Frequency
        read_ms=($end-$begin)*1000.0/[Diagnostics.Stopwatch]::Frequency;provider_entries=$samples.Count
        scope=@($scope.Values);entries=$entries}
    [IO.File]::AppendAllText($Output,($record|ConvertTo-Json -Depth 6 -Compress)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
}

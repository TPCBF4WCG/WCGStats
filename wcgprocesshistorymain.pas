UNIT WCGProcessHistoryMain;

{$mode objfpc}{$H+}

INTERFACE

USES Classes,
     SysUtils,
     Forms,
     Controls,
     Graphics,
     Dialogs,
     Menus,
     ComCtrls,
     Grids,
     EditBtn,
     Buttons;

Type

{ tForm1 }

 tForm1 = CLASS (tForm)
                BitBtn1: TBitBtn;
                BitBtn2: TBitBtn;
                BitBtn3: TBitBtn;
                BitBtn4: TBitBtn;
                FileNameEdit1: TFileNameEdit;
                MainMenu1: TMainMenu;
                StatusBar1: TStatusBar;
                StringGrid1: TStringGrid;
                procedure BitBtn1Click(Sender: TObject);
                procedure BitBtn2Click(Sender: TObject);
                procedure BitBtn3Click(Sender: TObject);
                procedure BitBtn4Click(Sender: TObject);
                procedure FileNameEdit1Change(Sender: TObject);
              PRIVATE

              PUBLIC

              end;

Var Form1 : tForm1;

IMPLEMENTATION

//USES SysUtils;

{$R *.lfm}

USES DateUtils;

Const StatusInProgress          =  0;
      StatusError               =  1;
      StatusNoReply             =  2;
      StatusPendingValidation   =  3;
      StatusValid               =  4;
      StatusPendingVerification =  6;
      StatusTooLate             =  7;
      StatusUserAborted         = 12;
      StatusServerAborted       = 13;

Type tWURecord = Record
                   AppVersionNumber : SmallInt;
                   DeviceName       : String [20];

                   SentTime         : tDateTime;
                   DueTime          : tDateTime;
                   ReturnedTime     : tDateTime;

                   ElapsedTime      : Double;
                   CPUHours         : Double;

                   ClaimedCredit    : Double;
                   GrantedCredit    : Double;

                   OS               : String [30];
                   OSVersion        : String [50];
                   owned            : Boolean;
                   ResultID         : Cardinal;
                   ResultName       : String [80];
                   Status           : Byte;
                   StatusName       : String [20];
                   WorkUnitID       : Cardinal;
                 end; // tWURecord

Const cWUDBFile      = 'C:\TEMP\WUDB.DAT';
      cWULogFile     = 'C:\TEMP\WUDB.LOG';

Var DBExists : Boolean;

    WUArray  : Array of tWURecord;


Procedure SplitCSVLine (    S : String;
                        Var L : tStringList);
Var p     : Integer;
    Count : Integer;
    F     : String;
begin
  Count := 0;
  L.Clear;
  F     := '';
  repeat
    Inc (Count);

    if S[1] = '"'
      then begin
             //Delete (S, 1, 1);
             p := 1;
             repeat Inc (p) until S [p] = '"';
             Inc (p); // get the comma
           end
      else p := Pos (',', S);

    if p > 0
      then begin // all but the last column
            F := Copy (S, 1, p-1);
            Delete (S, 1, p);
            if (p > 1) AND (F [1] <> ',')
              then begin
                     if F[1]          = '"' then Delete (F, 1, 1);
                     if F[Length (F)] = '"' then Delete (F, Length (F), 1);
                   end
              else begin // an empty field
                      F := '';
                    end;
           end
      else begin // the last column
             F  := S;
             if F [1] <> ','
               then begin // not an empty field
                      if F[1]          = '"' then Delete (F, 1, 1);
                      if F[Length (F)] = '"' then Delete (F, Length (F), 1);
                    end
               else begin // an empty field
                      F := '';
                   end;

           end;
    L.Add (F);
  until Count = 17;
end; // SplitCSVLine

Procedure ShowStatus (S : String);
begin
  Form1.StatusBar1.SimpleText := S;
  Form1.Repaint;
end; // ShowStatus

Function Str2DateTime (S : String) : tDateTime;  // adjust WCG CSV date/time to LCL expected format
begin
  if S = ''
    then Result := 0
    else Result := ISO8601ToDate (S, TRUE);
end; // Srtr2DateTime

Procedure ReadDBFile (Const WUDBFilename : String);
Var F     : File;
    Index : Integer;
begin
  Assign (F, WUDBFilename);
  ReSet  (F, 1);
  SetLength (WUArray, 0);  Index := -1;
  while NOT EOF (F) do
    begin
      Inc (Index); Setlength (WUArray, Index+1);
      BlockRead (F, WUArray [Index], SizeOf (tWURecord));
    end;
  Close (F);
end; // ReadDBFile

Procedure SaveDBFile (Const WUDBFilename : String);
Var F     : File;
    Index : Integer;
begin
  AssignFile (F, WUDBFilename);
  ReWrite    (F, 1);
  Index := High (WUArray);
  for Index := 0 to High (WUArray) do
    begin
      BlockWrite (F, WUArray [Index], SizeOf (tWURecord));
    end;
  Close (F);
end; // SaveDBFile

Function GetWUIndex (WU : tWURecord) : Integer;
Var i : Integer;
begin
  for i := 0 to High (WUArray) do
    begin
      if (WUArray [i].WorkUnitID = WU.WorkUnitID) then
        begin
          BREAK;
        end;
    end; // for i
  GetWUIndex := i;
end; // GetWUIndex

Procedure WriteWUtoDB (Var NewWU : tWURecord);
Var Changed : Boolean;
    NoRecs  : Integer;
    WUIndex : Integer;
begin
   if DBExists
     then begin
            // check if WU ID already exists
            WUIndex := GetWUIndex (NewWU);
            //
            NoRecs := High (WUArray);
            if WUIndex < NoRecs
              then begin  // existing WorkUnit?

                     if WUArray[WUIndex].Status = NewWU.Status then
                       begin //  no change, nothing to save
                         EXIT; // get me outta here!
                       end;

                     // lets check if there is any change that needs to update WU in DB
                     Changed := FALSE;
                     case WUArray[WUIndex].Status of
                       StatusInProgress          {  0 } : Changed := TRUE;
                       StatusError               {  1 } : Changed := FALSE; // do nothing!?
                       StatusNoReply             {  2 } : Changed := TRUE;
                       StatusPendingValidation   {  3 } : Changed := TRUE;
                       StatusValid               {  4 } : Changed := FALSE;
                       StatusPendingVerification {  6 } : Changed := TRUE;
                       StatusTooLate             {  7 } : Changed := FALSE;
                       StatusUserAborted         { 12 } : Changed := FALSE;
                       StatusServerAborted       { 13 } : Changed := FALSE;
                       else                      { ?? }   begin
                                                            ShowMessage (  'Unknown Status encountered  '
                                                                         + IntToStr (NewWU.Status)
                                                                         + ':'
                                                                         + NewWU.StatusName+' ['
                                                                         + IntToStr (WUArray [WUIndex].WorkunitID)
                                                                         + ']');
                                                          end;
                     end; // case old status
                     if Changed then
                       begin
                         ShowStatus ('Changed WU  '+IntToStr (NewWU.WorkUnitID)+': '+IntToStr (WUArray[WUIndex].Status)+'->'+IntToStr (NewWU.Status));
                         WUArray [WUIndex] := NewWU;
                       end; // changed needs to be written back
                   end
              else begin // adding new WU to end of database
                     Inc (WUIndex); //?????????
                     SetLength (WUArray, WUIndex+1);
                     WUArray [WUIndex] := NewWU;
                     ShowStatus ('1 Adding new WU!  ('+IntToStr (WUIndex)+')');
                    end;
          end
     else begin // new DB, just append WUs
            WUIndex := High (WUArray);
            Inc (WUIndex); //??????
            SetLength (WUArray, WUIndex+1);
            WUArray [WUIndex] := NewWU;
            ShowStatus ('Writing new WU!  ('+IntToStr (WUIndex)+')');
          end;
end; //WriteWUtoDB

Procedure ReadCSVFile (Const CSVFileName : String);
Var CSVFile    : TextFile;
    SL         : tStringList;
    s          : String;
    i          : Integer;
    NoGridRows : Integer;
    WU         : tWURecord;
begin
  Form1.StringGrid1.Clean; // !!!!!!!!!
  Form1.StringGrid1.FixedRows := 1;
  Form1.StringGrid1.RowCount  := 2;

  if NOT FileExists (CSVFilename) then
    begin
      ShowMessage(CSVFilename+' doesn''t exist');
      EXIT;
    end;

  if NOT FileExists (cWUDBFile) // first time, create new database file
    then begin
           SetLength (WUArray, 0);
           DBExists := FALSE;
         end
    else begin
           ReadDBFile (cWUDBFile);
           DBExists := TRUE;
         end;

  SL         := tStringList.Create;
  NoGridRows := 0;                  // of StringGrid

  AssignFile (CSVFile, CSVFilename);
  ReSet (CSVFile);

  TRY
    for i := 1 to 6 do ReadLn (CSVFile, S); // read over the header lines

    while NOT EOF (CSVFile) do
      begin
        ReadLn (CSVFile, S);
        SplitCSVLine (S, SL);
        Inc (NoGridRows);
        // Assign to WU Record Values;
        with WU do
          begin
            AppVersionNumber := StrToInt     (SL [ 0]);
            ClaimedCredit    := StrToFloat   (SL [ 1]);
            CPUHours         := StrToFloat   (SL [ 2]);
            DeviceName       :=               SL [ 3];
            DueTime          := Str2DateTime (SL [ 4]);
            ElapsedTime      := StrToFloat   (SL [ 5]);
            GrantedCredit    := StrToFloat   (SL [ 6]);
            OS               :=               SL [ 7];
            OSVersion        :=               SL [ 8];
          //owned            :=               SL [ 9];
            ResultID         := StrToInt     (SL [10]);
            ResultName       :=               SL [11];
            ReturnedTime     := Str2DateTime (SL [12]);
            SentTime         := Str2DateTime (SL [13]);
            Status           := StrToInt     (SL [14]);
            StatusName       :=               SL [15];
            WorkUnitID       := StrToInt     (SL [16]);
          end; // with WU

        // Write new WU to DB, update existing WU, or do nothing if no change in status of WU
        WriteWUtoDB (WU);

        // add to StringGrid1
        Form1.StringGrid1.InsertRowWithValues (NoGridRows, [SL[ 0], SL[ 1], SL[ 2], SL[ 3],
                                                            SL[ 4], SL[ 5], SL[ 6], SL[ 7],
                                                            SL[ 8], SL[ 9], SL[10], SL[11],
                                                            SL[12], SL[13], SL[14], SL[15], SL[16]
                                                       ]
                                              );
        if (NoGridRows MOD 25) = 0 then
          begin
            // Form1.StringGrid1.AutoSizeColumns;
            ShowStatus (IntToStr (NoGridRows)+'  WUs found in '+CSVFilename );
            Form1.Repaint;
          end;

      end; // while NOT EOF (CSVFile);

  FINALLY
    CloseFile (CSVFile);
  end; // TRY

  Form1.StringGrid1.AutoSizeColumns;
  ShowStatus (IntToStr (NoGridRows)+'  WUs found in '+CSVFilename );
  Form1.Repaint;

  SL.Free;

  SaveDBFile (cWUDBFile);

end; // ReadCSVFile

Procedure ReadDBForStats;
Var CreditTotalWCG,
    CPUHoursTotalWCG,
    CreditPVaTotalWCG,
    HoursPVaTotalWCG,
    CreditPVeTotalWCG,
    HoursPVeTotalWCG,
    HoursTooLateTotal  : Double;
    WULogFile          : Text;
    WUValidatedCount,
    WUPVaCount,
    WUPVeCount,
    WUTooLateCount     : Integer;
    RecCount           : Integer;
begin
  if NOT FileExists (cWUDBFile) then // first time, create new database file
    begin
      ShowMessage ('Database file doesn''t exist yet!');
      EXIT;
    end;

  ReadDBFile (cWUDBFile);

  RecCount          := -1;  // ???

  WUValidatedCount  := 0;
  WUPVaCount        := 0;
  WUPVeCount        := 0;
  WUTooLateCount    := 0;
  CreditTotalWCG    := 0.0;
  CPUHoursTotalWCG  := 0.0;
  CreditPVaTotalWCG := 0.0;
  HoursPVaTotalWCG  := 0.0;
  CreditPVeTotalWCG := 0.0;
  HoursPVeTotalWCG  := 0.0;
  HoursTooLateTotal := 0.0;

  while RecCount < High (WUArray) do
    begin
      Inc (RecCount);
      case WUArray [RecCount].Status of
        StatusValid               : begin
                                      Inc (WUValidatedCount);
                                      CreditTotalWCG    := CreditTotalWCG    + WUArray [RecCount].GrantedCredit;
                                      CPUHoursTotalWCG  := CPUHoursTotalWCG  + WUArray [RecCount].CPUHours;
                                    end;
        StatusPendingValidation   : begin
                                      Inc (WUPVaCount);
                                      CreditPVaTotalWCG := CreditPVaTotalWCG + WUArray [RecCount].ClaimedCredit;
                                      HoursPVaTotalWCG  := HoursPVaTotalWCG  + WUArray [RecCount].CPUHours;
                                    end;
        StatusPendingVerification : begin
                                      Inc (WUPVeCount);
                                      CreditPVeTotalWCG := CreditPVeTotalWCG + WUArray [RecCount].ClaimedCredit;
                                      HoursPVeTotalWCG  := HoursPVeTotalWCG  + WUArray [RecCount].CPUHours;
                                    end;
        StatusTooLate             : begin
                                      Inc (WUTooLateCount);
                                      HoursTooLateTotal := HoursTooLateTotal + WUArray [RecCount].CPUHours;
                                    end;
      end; // case
    end; // while NOT EOF
  // ---------------------------------------------------------------------------
  AssignFile (WULogFile, cWULogFile);

  ReWrite (WULogFile);
  WriteLn (WULogFile, DateTimeToStr (Now));
  WriteLn (WULogFile, 'Collected WUs      : ', RecCount);
  WriteLn (WULogFile);
  WriteLn (WULogFile, 'Validated WUs      :', WUValidatedCount);
  WriteLn (WULogFile, 'Total Credit       :', CreditTotalWCG:10:2,'( BOINC=',CreditTotalWCG/7:10:2,')');
  WriteLn (WULogFile, 'Total Runtime      :', CPUHoursTotalWCG:10:2, ' (',CPUHoursTotalWCG/24:5:1,')');
  WriteLn (WULogFile, 'PVa WUs            :', WUPVaCount);
  WriteLn (WULogFile, 'PVa claimed Credit :', CreditPVaTotalWCG:10:2,'(BOINC=',CreditPVaTotalWCG/7:10:2,')');
  WriteLn (WULogFile, 'PVa Runtime        :', HoursPVaTotalWCG:10:2, ' (',HoursPVaTotalWCG/24:5:1,')');
  WriteLn (WULogFile, 'PVe WUs            :', WUPVeCount);
  WriteLn (WULogFile, 'PVe claimed Credit :', CreditPVeTotalWCG:10:2,'(BOINC=',CreditPVeTotalWCG/7:10:2,')');
  WriteLn (WULogFile, 'PVe Runtime        :', HoursPVeTotalWCG:10:2, ' (',HoursPVeTotalWCG/24:5:1,')');
  WriteLn (WULogFile, 'WUs Too late       :', WUTooLateCount);
  WriteLn (WULogFile, 'Too Late Runtime   :', HoursTooLateTotal:10:2, ' (',HoursTooLateTotal/24:5:1,')');

  CloseFile (WULogFile);
  // ---------------------------------------------------------------------------

  ShowStatus ('Stats for '+IntToStr (RecCount+1)+' WUs read');
end; // ReadDBForStats

{ tForm1 }

Procedure tForm1.BitBtn1Click (Sender : tObject);
begin
  Application.Terminate;
end;

Procedure tForm1.BitBtn2Click (Sender : tObject);
Var s : String;
begin
  S := Form1.FilenameEdit1.Text;
  Form1.FileNameEdit1.Filename := S;
  ReadCSVFile (S);
end;

Procedure tForm1.BitBtn3Click (Sender: tObject);
Var s : String;
begin
  S := Form1.FilenameEdit1.Text;
  Form1.FileNameEdit1.Filename := S;
  ReadDBForStats;
end;

Procedure tForm1.BitBtn4Click (Sender : tObject);
Var FileList : Text;
    S        : String;
begin
  S := Form1.FilenameEdit1.Text;
  AssignFile (Filelist, S);
  ReSet (Filelist);
  while NOT EOF (FileList) do
    begin
      ReadLn (FileList, S);
      Form1.FileNameEdit1.Filename := S;
      ReadCSVFile (S);
    end;
  CloseFile (Filelist);
  ReadDBForStats;
end;

Procedure tForm1.FileNameEdit1Change (Sender : tObject);
begin
  Form1.FilenameEdit1.InitialDir := Form1.FilenameEdit1.FileName;
end;

end.


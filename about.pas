{*************************************************************************************
  This file is part of Transmission Remote GUI.
  Copyright (c) 2008-2019 by Yury Sidorov and Transmission Remote GUI working group.

  Transmission Remote GUI is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation; either version 2 of the License, or
  (at your option) any later version.

  Transmission Remote GUI is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with Transmission Remote GUI; if not, write to the Free Software
  Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA

  In addition, as a special exception, the copyright holders give permission to 
  link the code of portions of this program with the
  OpenSSL library under certain conditions as described in each individual
  source file, and distribute linked combinations including the two.

  You must obey the GNU General Public License in all respects for all of the
  code used other than OpenSSL.  If you modify file(s) with this exception, you
  may extend this exception to your version of the file(s), but you are not
  obligated to do so.  If you do not wish to do so, delete this exception
  statement from your version.  If you delete this exception statement from all
  source files in the program, then also delete it here.
*************************************************************************************}

unit About;

{$mode objfpc}{$H+}{$J-}

interface

uses
  Classes, SysUtils, FileUtil, LResources, Forms, Controls, Graphics,
  Dialogs, StdCtrls, ComCtrls, ExtCtrls, ButtonPanel, lclversion, BuildInfo,
  ssl_openssl3, ssl_openssl3_lib, fpjson;

resourcestring
  SErrorCheckingVersion = 'Error checking for new version.';
  SNewVersionFound = 'A new version of %s is available.' + LineEnding +
                    'Your current version: %s' + LineEnding +
                    'The new version: %s' + LineEnding + LineEnding +
                    'Do you wish to open the Downloads web page?';
  SLatestVersion = 'No updates have been found.' + LineEnding + 'You are running the latest version of %s.';

type

  { TAboutForm }

  TAboutForm = class(TForm)
    Bevel1: TBevel;
    Buttons: TButtonPanel;
    edLicense: TMemo;
    imgTransmission: TImage;
    imgSynapse: TImage;
    imgLazarus: TImage;
    txHomePage: TLabel;
    txAuthor: TLabel;
    txVersion: TLabel;
    txAppName: TLabel;
    Page: TPageControl;
    tabAbout: TTabSheet;
    tabLicense: TTabSheet;
    txVersFPC: TLabel;
    procedure FormCreate(Sender: TObject);
    procedure imgDonateClick(Sender: TObject);
    procedure imgLazarusClick(Sender: TObject);
    procedure imgSynapseClick(Sender: TObject);
    procedure txHomePageClick(Sender: TObject);
  private
    { private declarations }
  public
    { public declarations }
  end;

procedure CheckNewVersion(Async: boolean = True);
procedure GoHomePage;
procedure GoGitHub;

implementation

uses Main, utils, httpsend;

type

  { TCheckVersionThread }

  TCheckVersionThread = class(TThread)
  private
    FHttp: THTTPSend;
    FError: string;
    FVersion: string;
    FExit: boolean;

    procedure CheckResult;
    function GetIntVersion(const Ver: string): integer;
  protected
    procedure Execute; override;
  end;

var
  CheckVersionThread: TCheckVersionThread;

procedure CheckNewVersion(Async: boolean);
begin
  if CheckVersionThread <> nil then
    exit;
  Ini.WriteInteger('Interface', 'LastNewVersionCheck', Trunc(Now));
  CheckVersionThread:=TCheckVersionThread.Create(True);
  CheckVersionThread.FreeOnTerminate:=True;
  if Async then
    CheckVersionThread.Suspended:=False
  else begin
    CheckVersionThread.Execute;
    CheckVersionThread.FExit:=True;
    CheckVersionThread.Suspended:=False;
  end;
end;

procedure GoHomePage;
begin
  AppBusy;
  OpenURL('https://github.com/lighterowl/transgui/releases/latest');
  AppNormal;
end;

procedure GoGitHub;
begin
  AppBusy;
  OpenURL('https://github.com/lighterowl/transgui');
  AppNormal;
end;

{ TCheckVersionThread }

procedure TCheckVersionThread.CheckResult;
begin
  ForceAppNormal;
  if FError <> '' then begin
    MessageDlg(SErrorCheckingVersion + LineEnding + FError, mtError, [mbOK], 0);
    exit;
  end;

  if GetIntVersion(AppVersion) >= GetIntVersion(FVersion)  then begin
    MessageDlg(Format(SLatestVersion, [AppName]), mtInformation, [mbOK], 0);
    exit;
  end;

  if MessageDlg(Format(SNewVersionFound, [AppName, AppVersion, FVersion]), mtConfirmation, mbYesNo, 0) <> mrYes then
    exit;

  Application.ProcessMessages;
  AppBusy;
  OpenURL('https://github.com/lighterowl/transgui/releases');
  AppNormal;
end;

function TCheckVersionThread.GetIntVersion(const Ver: string): integer;
var
  v: string;
  vi, i, j: integer;
begin
  Result:=0;
  v:=Ver;
  for i:=1 to 3 do begin
    if v = '' then
      vi:=0
    else begin
      j:=Pos('.', v);
      if j = 0 then
        j:=MaxInt;
      vi:=StrToIntDef(Copy(v, 1, j - 1), 0);
      Delete(v, 1, j);
    end;
    Result:=Result shl 8 or vi;
  end;
end;

procedure TCheckVersionThread.Execute;
var
  parsed: TJSONObject;
begin
  if not FExit then begin
    try
      FHttp:=THTTPSend.Create;
      try
        if RpcObj.Http.ProxyHost <> '' then begin
          FHttp.ProxyHost:=RpcObj.Http.ProxyHost;
          FHttp.ProxyPort:=RpcObj.Http.ProxyPort;
          FHttp.ProxyUser:=RpcObj.Http.ProxyUser;
          FHttp.ProxyPass:=RpcObj.Http.ProxyPass;
        end;
        if FHttp.HTTPMethod('GET', 'https://api.github.com/repos/lighterowl/transgui/releases/latest') then begin
          if FHttp.ResultCode = 200 then begin
            parsed := GetJSON(FHttp.Document) as TJSONObject;
            FVersion := Copy(parsed.Strings['name'], 2);
            parsed.Free;
          end
          else
            FError:=Format('HTTP error: %d', [FHttp.ResultCode]);
        end
        else
          FError:=FHttp.Sock.LastErrorDesc;
      finally
        FHttp.Free;
      end;
    except
      FError:=Exception(ExceptObject).Message;
    end;
    if (FError <> '') or (GetIntVersion(FVersion) > GetIntVersion(AppVersion)) or Suspended then
      if Suspended then
        CheckResult
      else
        Synchronize(@CheckResult);
  end;
  if not Suspended then
    CheckVersionThread:=nil;
end;

{ TAboutForm }

procedure TAboutForm.imgSynapseClick(Sender: TObject);
begin
  AppBusy;
  OpenURL('http://synapse.ararat.cz');
  AppNormal;
end;

procedure TAboutForm.txHomePageClick(Sender: TObject);
begin
  GoHomePage;
end;

procedure TAboutForm.FormCreate(Sender: TObject);
begin
  bidiMode := GetBiDi();
  BorderStyle:=bsSizeable;
  txAppName.Caption:=AppName;
  txVersion.Caption:=Format(txVersion.Caption, [AppVersion, BuildInfo.GIT_COMMIT]);
  Page.ActivePageIndex:=0;

  txVersFPC.caption := 'Fpc : ' + {$I %FPCVERSION%} + '   Lazarus : ' +lcl_version;
end;

procedure TAboutForm.imgDonateClick(Sender: TObject);
begin
  GoGitHub;
end;

procedure TAboutForm.imgLazarusClick(Sender: TObject);
begin
  AppBusy;
  OpenURL('https://www.lazarus-ide.org');
  AppNormal;
end;

initialization
  {$I about.lrs}

end.

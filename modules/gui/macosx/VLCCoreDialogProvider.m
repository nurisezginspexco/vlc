/*****************************************************************************
 * VLCCoreDialogProvider.m: Mac OS X Core Dialogs
 *****************************************************************************
 * Copyright (C) 2005-2016 VLC authors and VideoLAN
 * $Id$
 *
 * Authors: Derk-Jan Hartman <hartman at videolan dot org>
 *          Felix Paul Kühne <fkuehne at videolan dot org>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#import "VLCMain.h"
#import "VLCCoreDialogProvider.h"
#import "misc.h"

/* for the icon in our custom error panel */
#import <ApplicationServices/ApplicationServices.h>

@interface VLCCoreDialogProvider ()

- (void)displayError:(NSArray *)dialogData;

- (void)displayLoginDialog:(NSArray *)dialogData;

- (void)displayQuestion:(NSArray *)dialogData;

- (void)displayProgressDialog:(NSArray *)dialogData;

- (void)updateDisplayedProgressDialog:(NSArray *)dialogData;

@end


static void displayErrorCallback(void *p_data,
                                 const char *psz_title,
                                 const char *psz_text)
{
    @autoreleasepool {
        VLCCoreDialogProvider *dialogProvider = (__bridge VLCCoreDialogProvider *)p_data;
        [dialogProvider performSelectorOnMainThread:@selector(displayError:)
                                         withObject:@[toNSStr(psz_title),
                                                      toNSStr(psz_text)]
                                      waitUntilDone:NO];
    }
}

static void displayLoginCallback(void *p_data,
                                 vlc_dialog_id *p_id,
                                 const char *psz_title,
                                 const char *psz_text,
                                 const char *psz_default_username,
                                 bool b_ask_store)
{
    @autoreleasepool {
        VLCCoreDialogProvider *dialogProvider = (__bridge VLCCoreDialogProvider *)p_data;
        [dialogProvider performSelectorOnMainThread:@selector(displayLoginDialog:)
                                         withObject:@[[NSValue valueWithPointer:p_id],
                                                      toNSStr(psz_title),
                                                      toNSStr(psz_text),
                                                      toNSStr(psz_default_username),
                                                      @(b_ask_store)]
                                      waitUntilDone:NO];
    }
}

static void displayQuestionCallback(void *p_data,
                                    vlc_dialog_id *p_id,
                                    const char *psz_title,
                                    const char *psz_text,
                                    vlc_dialog_question_type i_type,
                                    const char *psz_cancel,
                                    const char *psz_action1,
                                    const char *psz_action2)
{
    @autoreleasepool {
        VLCCoreDialogProvider *dialogProvider = (__bridge  VLCCoreDialogProvider *)p_data;
        [dialogProvider performSelectorOnMainThread:@selector(displayQuestion:)
                                         withObject:@[[NSValue valueWithPointer:p_id],
                                                      toNSStr(psz_title),
                                                      toNSStr(psz_text),
                                                      @(i_type),
                                                      toNSStr(psz_cancel),
                                                      toNSStr(psz_action1),
                                                      toNSStr(psz_action2)]
                                      waitUntilDone:NO];
    }
}

static void displayProgressCallback(void *p_data,
                                    vlc_dialog_id *p_id,
                                    const char *psz_title,
                                    const char *psz_text,
                                    bool b_indeterminate,
                                    float f_position,
                                    const char *psz_cancel)
{
    @autoreleasepool {
        VLCCoreDialogProvider *dialogProvider = (__bridge VLCCoreDialogProvider *)p_data;
        [dialogProvider performSelectorOnMainThread:@selector(displayProgressDialog:)
                                         withObject:@[[NSValue valueWithPointer:p_id],
                                                      toNSStr(psz_title),
                                                      toNSStr(psz_text),
                                                      @(b_indeterminate),
                                                      @(f_position),
                                                      toNSStr(psz_cancel)]
                                      waitUntilDone:NO];
    }
}

static void cancelCallback(void *p_data,
                           vlc_dialog_id *p_id)
{
    @autoreleasepool {
        [NSApp stopModalWithCode: 0];
    }
}

static void updateProgressCallback(void *p_data,
                                   vlc_dialog_id *p_id,
                                   float f_value,
                                   const char *psz_text)
{
    @autoreleasepool {
        VLCCoreDialogProvider *dialogProvider = (__bridge VLCCoreDialogProvider *)p_data;
        [dialogProvider performSelectorOnMainThread:@selector(updateDisplayedProgressDialog:)
                                         withObject:@[[NSValue valueWithPointer:p_id],
                                                      @(f_value),
                                                      toNSStr(psz_text)]
                                      waitUntilDone:NO];
    }
}

@implementation VLCCoreDialogProvider

- (instancetype)init
{
    self = [super init];

    if (self) {
        msg_Dbg(getIntf(), "Register dialog provider");
        [NSBundle loadNibNamed:@"CoreDialogs" owner: self];

        intf_thread_t *p_intf = getIntf();
        /* subscribe to various interactive dialogues */

        const vlc_dialog_cbs cbs = {
            displayErrorCallback,
            displayLoginCallback,
            displayQuestionCallback,
            displayProgressCallback,
            cancelCallback,
            updateProgressCallback
        };

        vlc_dialog_provider_set_callbacks(p_intf, &cbs, (__bridge void *)self);
    }

    return self;
}

- (void)dealloc
{
    msg_Dbg(getIntf(), "Deinitializing dialog provider");

    intf_thread_t *p_intf = getIntf();
    vlc_dialog_provider_set_callbacks(p_intf, NULL, NULL);
}

-(void)awakeFromNib
{
    _progressCancelled = NO;
    [authenticationLoginLabel setStringValue: _NS("Username")];
    [authenticationPasswordLabel setStringValue: _NS("Password")];
    [authenticationCancelButton setTitle: _NS("Cancel")];
    [authenticationOkButton setTitle: _NS("OK")];
    [authenticationStorePasswordCheckbox setTitle:_NS("Remember")];

    [progressCancelButton setTitle: _NS("Cancel")];
    [progressIndicator setUsesThreadedAnimation: YES];
}

- (void)displayError:(NSArray *)dialogData
{
    NSAlert *alert = [NSAlert alertWithMessageText:dialogData[0]
                                     defaultButton:_NS("OK")
                                   alternateButton:nil
                                       otherButton:nil
                         informativeTextWithFormat:@"%@", dialogData[1]];
    [alert setAlertStyle:NSCriticalAlertStyle];
    [alert runModal];
}

- (void)displayLoginDialog:(NSArray *)dialogData
{
    [authenticationTitleLabel setStringValue:dialogData[1]];
    authenticationWindow.title = dialogData[1];
    [authenticationDescriptionLabel setStringValue:dialogData[2]];

    [authenticationLoginTextField setStringValue:dialogData[3]];
    [authenticationPasswordTextField setStringValue:@""];

    authenticationStorePasswordCheckbox.hidden = ![dialogData[4] boolValue];
    authenticationStorePasswordCheckbox.state = NSOffState;

    [authenticationWindow center];
    NSInteger returnValue = [NSApp runModalForWindow:authenticationWindow];
    [authenticationWindow close];

    NSString *username = authenticationLoginTextField.stringValue;
    NSString *password = authenticationPasswordTextField.stringValue;

    vlc_dialog_id_post_login([dialogData[0] pointerValue],
                             username ? [username UTF8String] : NULL,
                             password ? [password UTF8String] : NULL,
                             authenticationStorePasswordCheckbox.state == NSOnState);
}

- (IBAction)authenticationDialogAction:(id)sender
{
    if ([[sender title] isEqualToString: _NS("OK")])
        [NSApp stopModalWithCode: 1];
    else
        [NSApp stopModalWithCode: 0];
}

- (void)displayQuestion:(NSArray *)dialogData
{
    NSAlert *alert = [NSAlert alertWithMessageText:dialogData[1]
                                     defaultButton:dialogData[5]
                                   alternateButton:dialogData[6]
                                       otherButton:dialogData[4]
                         informativeTextWithFormat:@"%@", dialogData[2]];

    switch ([dialogData[3] intValue]) {
        case VLC_DIALOG_QUESTION_WARNING:
            [alert setAlertStyle:NSWarningAlertStyle];
            break;
        case VLC_DIALOG_QUESTION_CRITICAL:
            [alert setAlertStyle:NSCriticalAlertStyle];
            break;
        default:
            [alert setAlertStyle:NSInformationalAlertStyle];
            break;
    }

    NSInteger returnValue = [alert runModal];
    switch (returnValue) {
        case NSAlertAlternateReturn:
            vlc_dialog_id_post_action([dialogData[0] pointerValue], 2);
            break;

        case NSAlertOtherReturn:
            vlc_dialog_id_post_action([dialogData[0] pointerValue], 3);
            break;

        default:
            vlc_dialog_id_post_action([dialogData[0] pointerValue], 1);
            break;
    }

}

- (void)displayProgressDialog:(NSArray *)dialogData
{
    progressTitleLabel.stringValue = dialogData[1];
    progressWindow.title = dialogData[1];

    progressDescriptionLabel.stringValue = dialogData[2];

    progressIndicator.indeterminate = [dialogData[3] boolValue];
    progressIndicator.doubleValue = [dialogData[4] doubleValue];

    if ([dialogData[5] length] > 0) {
        progressCancelButton.title = dialogData[5];
    } else {
        progressCancelButton.title = _NS("Cancel");
    }

    [progressIndicator startAnimation:self];

    [progressWindow center];
    NSInteger returnValue = [NSApp runModalForWindow:progressWindow];
    [progressWindow close];

    [progressIndicator stopAnimation:self];

    if (returnValue == -1)
        vlc_dialog_id_dismiss([dialogData[0] pointerValue]);
}

- (void)updateDisplayedProgressDialog:(NSArray *)dialogData

{
    if (!progressIndicator.indeterminate) {
        progressIndicator.doubleValue = [dialogData[1] doubleValue];
        progressDescriptionLabel.stringValue = dialogData[2];
    }
}

- (IBAction)progressDialogAction:(id)sender
{
    [NSApp stopModalWithCode: -1];
}

@end

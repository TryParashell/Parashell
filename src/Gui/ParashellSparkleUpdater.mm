/***************************************************************************
 *   Copyright (c) 2026 Parashell                                          *
 *                                                                         *
 *   This file is part of Parashell.                                       *
 *                                                                         *
 *   Parashell is free software: you can redistribute it and/or modify     *
 *   it under the terms of the GNU Lesser General Public License as        *
 *   published by the Free Software Foundation, either version 2.1 of the  *
 *   License, or (at your option) any later version.                       *
 *                                                                         *
 ***************************************************************************/

#import <Sparkle/Sparkle.h>

#include "ParashellSparkleUpdater.h"

namespace
{

SPUStandardUpdaterController* g_parashellUpdaterController = nil;

SPUStandardUpdaterController* parashellUpdaterController()
{
    if (g_parashellUpdaterController == nil) {
        g_parashellUpdaterController =
            [[SPUStandardUpdaterController alloc] initWithStartingUpdater:YES
                                                         updaterDelegate:nil
                                                      userDriverDelegate:nil];
    }
    return g_parashellUpdaterController;
}

}  // namespace

namespace Gui
{

void parashellSparkleStartUpdater(bool automaticChecksEnabled)
{
    @autoreleasepool {
        SPUStandardUpdaterController* controller = parashellUpdaterController();
        controller.updater.automaticallyChecksForUpdates = automaticChecksEnabled ? YES : NO;
    }
}

void parashellSparkleCheckForUpdatesInBackground(bool automaticChecksEnabled)
{
    @autoreleasepool {
        SPUStandardUpdaterController* controller = parashellUpdaterController();
        controller.updater.automaticallyChecksForUpdates = automaticChecksEnabled ? YES : NO;
        if (automaticChecksEnabled) {
            [controller.updater checkForUpdatesInBackground];
        }
    }
}

void parashellSparkleCheckForUpdates()
{
    @autoreleasepool {
        SPUStandardUpdaterController* controller = parashellUpdaterController();
        [controller checkForUpdates:nil];
    }
}

}  // namespace Gui

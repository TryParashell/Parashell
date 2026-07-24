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

#ifndef GUI_PARASHELLSPARKLEUPDATER_H
#define GUI_PARASHELLSPARKLEUPDATER_H

namespace Gui
{

void parashellSparkleStartUpdater(bool automaticChecksEnabled);

void parashellSparkleCheckForUpdatesInBackground(bool automaticChecksEnabled);

void parashellSparkleCheckForUpdates();

}  // namespace Gui

#endif  // GUI_PARASHELLSPARKLEUPDATER_H

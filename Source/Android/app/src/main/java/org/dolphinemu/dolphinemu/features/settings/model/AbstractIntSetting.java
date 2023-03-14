// SPDX-License-Identifier: GPL-2.0-or-later

package org.dolphinemu.dolphinemu.features.settings.model;

import androidx.annotation.NonNull;

public interface AbstractIntSetting extends AbstractSetting
{
  int getInt(@NonNull Settings settings);

  void setInt(@NonNull Settings settings, int newValue);
}

/*
 * Copyright (c) 2013-2021 Thomas Isaac Lightburn
 *
 *
 * This file is part of OpenKJ.
 *
 * OpenKJ is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

#ifndef OPENKJ_OKJFMT_H
#define OPENKJ_OKJFMT_H

// fmt (used by spdlog) no longer falls back to operator<< since fmt 9, so
// formatters for the Qt types we log are provided here.

#include <QByteArray>
#include <QString>
#include <ostream>
#include <string_view>
#include <spdlog/fmt/fmt.h>
#include "okjfmt.h"

std::ostream& operator<<(std::ostream& os, const QString& s);

template<>
struct fmt::formatter<QString> : fmt::formatter<std::string_view> {
    template<typename FormatContext>
    auto format(const QString &s, FormatContext &ctx) const -> decltype(ctx.out()) {
        const QByteArray utf8 = s.toUtf8();
        return fmt::formatter<std::string_view>::format(std::string_view(utf8.constData(), utf8.size()), ctx);
    }
};

template<>
struct fmt::formatter<QByteArray> : fmt::formatter<std::string_view> {
    template<typename FormatContext>
    auto format(const QByteArray &b, FormatContext &ctx) const -> decltype(ctx.out()) {
        return fmt::formatter<std::string_view>::format(std::string_view(b.constData(), b.size()), ctx);
    }
};

#endif //OPENKJ_OKJFMT_H

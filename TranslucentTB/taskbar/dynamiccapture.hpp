#pragma once
#include <windows.h>
#include <optional>
#include "dynamic/analysis.hpp"
#include "dynamic/geometry.hpp"

namespace Dynamic {
	class GdiCapture {
		HDC m_DC = nullptr;
		HBITMAP m_Bitmap = nullptr;
		HGDIOBJ m_Previous = nullptr;
		void *m_Bits = nullptr;
		int m_Width = 0, m_Height = 0;

	public:
		GdiCapture() = default;
		GdiCapture(const GdiCapture &) = delete;
		GdiCapture &operator=(const GdiCapture &) = delete;
		~GdiCapture() { Reset(); }

		void Reset() noexcept
		{
			if (m_Previous && m_DC) SelectObject(m_DC, m_Previous);
			if (m_Bitmap) DeleteObject(m_Bitmap);
			if (m_DC) DeleteDC(m_DC);
			m_DC = nullptr; m_Bitmap = nullptr; m_Previous = nullptr;
			m_Bits = nullptr; m_Width = m_Height = 0;
		}

		std::optional<Segment> Capture(Geometry geometry, std::optional<Rgb> previous) noexcept
		{
			const auto rect = geometry.rect;
			const int width = rect.right - rect.left, height = rect.bottom - rect.top;
			const HDC screen = GetDC(nullptr);
			if (!screen) return {};
			struct Release { HDC dc; ~Release() { ReleaseDC(nullptr, dc); } } release{ screen };
			if (width != m_Width || height != m_Height)
			{
				Reset();
				m_DC = CreateCompatibleDC(screen);
				BITMAPINFO info{};
				info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
				info.bmiHeader.biWidth = width;
				info.bmiHeader.biHeight = -height;
				info.bmiHeader.biPlanes = 1;
				info.bmiHeader.biBitCount = 32;
				info.bmiHeader.biCompression = BI_RGB;
				if (m_DC) m_Bitmap = CreateDIBSection(screen, &info, DIB_RGB_COLORS, &m_Bits, nullptr, 0);
				if (!m_Bitmap) { Reset(); return {}; }
				m_Previous = SelectObject(m_DC, m_Bitmap);
				if (!m_Previous || m_Previous == HGDI_ERROR) { m_Previous = nullptr; Reset(); return {}; }
				m_Width = width; m_Height = height;
			}
			if (!BitBlt(m_DC, 0, 0, width, height, screen, rect.left, rect.top, SRCCOPY | CAPTUREBLT) ||
				!GdiFlush()) return {};
			const auto stride = static_cast<std::size_t>(width) * 4;
			return Analyze({ { static_cast<const std::uint8_t *>(m_Bits), stride * height },
				static_cast<std::size_t>(width), static_cast<std::size_t>(height), stride,
				geometry.edge != Edge::Bottom }, previous);
		}
	};
}

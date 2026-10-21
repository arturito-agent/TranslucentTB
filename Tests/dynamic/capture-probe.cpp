#define NOMINMAX
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <iostream>
#include "../../TranslucentTB/taskbar/dynamiccapture.hpp"
#include "../../TranslucentTB/taskbar/dynamicdxgi.hpp"

int main()
{
	SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
	const auto taskbar = FindWindowW(L"Shell_TrayWnd", nullptr);
	MONITORINFO monitor{ sizeof(MONITORINFO) };
	RECT bar{};
	if (!taskbar || !GetWindowRect(taskbar, &bar) ||
		!GetMonitorInfoW(MonitorFromWindow(taskbar, MONITOR_DEFAULTTONEAREST), &monitor)) return 2;
	const auto m = monitor.rcMonitor;
	const auto geometry = Dynamic::SampleGeometry({m.left,m.top,m.right,m.bottom}, {bar.left,bar.top,bar.right,bar.bottom});
	if (!geometry) return 3;
	Dynamic::GdiCapture gdi;
	Dynamic::DxgiCapture dxgi;
	for (int i = 0; i < 3; ++i)
	{
		const auto a = gdi.Capture(*geometry, {});
		const auto b = dxgi.Capture(*geometry, {});
		std::cout << "sample=" << i << ",gdi=" << a.has_value() << ",dxgi=" << b.has_value()
			<< ",dxgi_hresult=0x" << std::hex << static_cast<unsigned long>(dxgi.LastError()) << std::dec;
		if (a) std::cout << ",gdi_rgb=" << unsigned(a->color.r) << ':' << unsigned(a->color.g) << ':' << unsigned(a->color.b);
		if (b) std::cout << ",dxgi_rgb=" << unsigned(b->color.r) << ':' << unsigned(b->color.g) << ':' << unsigned(b->color.b);
		std::cout << '\n';
		Sleep(500);
	}
	return 0;
}

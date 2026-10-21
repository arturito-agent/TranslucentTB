#pragma once

// Application appearance values. Dynamic is never a Windows ACCENT_STATE.
enum class AppearanceAccent {
	Normal = 0,
	Opaque = 1,
	Clear = 2,
	Blur = 3,
	Acrylic = 4,
	Dynamic = 5,
	DynamicV2 = 6
};

constexpr bool IsDynamicAccent(AppearanceAccent accent) noexcept
{
	return accent == AppearanceAccent::Dynamic || accent == AppearanceAccent::DynamicV2;
}

constexpr AppearanceAccent ScopedAppearanceAccent(AppearanceAccent accent, bool maximized) noexcept
{
	return accent == AppearanceAccent::DynamicV2 && !maximized ? AppearanceAccent::Opaque : accent;
}

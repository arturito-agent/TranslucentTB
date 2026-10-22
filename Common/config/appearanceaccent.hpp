#pragma once

// Application appearance values. Chameleon is never a Windows ACCENT_STATE.
enum class AppearanceAccent {
	Normal = 0,
	Opaque = 1,
	Clear = 2,
	Blur = 3,
	Acrylic = 4,
	Chameleon = 5
};

constexpr bool IsChameleonAccent(AppearanceAccent accent) noexcept
{
	return accent == AppearanceAccent::Chameleon;
}

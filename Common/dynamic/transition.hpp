#pragma once
#include "analysis.hpp"
#include <algorithm>
#include <cstdint>

namespace Dynamic {
// Fixed-size state; no frame history, allocations or screen captures.
struct Transition {
	Rgb from{}, to{}, current{};
	std::uint64_t started = 0;
	bool active = false;
	static constexpr std::uint64_t duration = 240;

	Rgb At(std::uint64_t now) const noexcept
	{
		if (!active || now - started >= duration) return to;
		const double t = static_cast<double>(now - started) / duration;
		const double eased = t * t * (3.0 - 2.0 * t);
		const auto mix = [eased](std::uint8_t a, std::uint8_t b) {
			return static_cast<std::uint8_t>(std::clamp(a + (b - a) * eased + 0.5, 0.0, 255.0));
		};
		return { mix(from.r, to.r), mix(from.g, to.g), mix(from.b, to.b) };
	}
	void Start(Rgb value, std::uint64_t now) noexcept
	{
		from = active ? At(now) : current;
		to = value; started = now; active = from != to;
		if (!active) current = to;
	}
	void Snap(Rgb value) noexcept { from = to = current = value; active = false; }
	Rgb Step(std::uint64_t now) noexcept
	{
		current = At(now);
		if (now - started >= duration) active = false;
		return current;
	}
};
}

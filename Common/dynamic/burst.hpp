#pragma once
#include <algorithm>
#include <cstdint>

namespace Dynamic {
// One bounded confirmation burst per event group; no periodic idle work.
struct Burst {
	unsigned remaining = 0;
	std::uint64_t due = 0;

	void Request(std::uint64_t now) noexcept
	{
		if (!remaining) due = now + 200;
		remaining = 3; // A new event during a burst gets fresh confirmation opportunities.
	}
	void Cancel() noexcept { remaining = 0; due = 0; }
	void Consumed(std::uint64_t now) noexcept
	{
		if (remaining && --remaining) due = now + (remaining == 2 ? 300 : 500);
		else due = 0;
	}
};
}

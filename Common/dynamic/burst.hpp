#pragma once
#include <cstdint>
#include <algorithm>

namespace Dynamic {
// A fixed three-read burst. Content noise cannot extend it or start >1 burst/2s.
// A real foreground/state change may supersede an old burst immediately.
struct Burst {
	unsigned remaining = 0;
	std::uint64_t due = 0, nextContent = 0;

	bool Request(std::uint64_t now, bool important = false) noexcept
	{
		if (!important && remaining) return false;
		due = important ? now + 200 : std::max(now + 200, nextContent);
		remaining = 3;
		nextContent = due + 1800;
		return true;
	}
	void Cancel() noexcept { remaining = 0; due = 0; nextContent = 0; }
	void Consumed(std::uint64_t now) noexcept
	{
		if (remaining && --remaining) due = now + (remaining == 2 ? 300 : 500);
		else due = 0;
	}
};
}

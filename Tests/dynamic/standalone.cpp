#include "dynamic/analysis.hpp"
#include "dynamic/transition.hpp"
#include "dynamic/events.hpp"
#include "config/appearanceaccent.hpp"
#include "dynamic/geometry.hpp"
#include <cstdlib>
#include <iostream>
#include <random>
#include <stdexcept>
#include <vector>

namespace {
	using Dynamic::Rgb;
	constexpr Rgb red{ 240, 0, 0 }, blue{ 0, 0, 240 }, green{ 0, 240, 0 };
	unsigned checks = 0;
	void Check(bool condition, const char *name)
	{
		++checks;
		if (!condition) throw std::runtime_error(name);
	}
	struct Image {
		std::vector<std::uint8_t> bytes;
		std::size_t width, height;
		bool vertical;
		explicit Image(const std::vector<Rgb> &steps, bool v = false) :
			bytes(steps.size() * 4), width(v ? 1 : steps.size()), height(v ? steps.size() : 1), vertical(v)
		{
			for (std::size_t i = 0; i < steps.size(); ++i)
			{
				const auto pos = i * 4;
				bytes[pos] = steps[i].b; bytes[pos + 1] = steps[i].g; bytes[pos + 2] = steps[i].r;
			}
		}
		Dynamic::Strip View() const { return { bytes, width, height, width * 4, vertical }; }
	};

	// Exhaustively enumerate contiguous intervals for an independent small-image oracle.
	Dynamic::Segment Oracle(const std::vector<Rgb> &pixels, std::optional<Rgb> previous)
	{
		Dynamic::Segment best;
		for (std::size_t a = 0; a < pixels.size(); ++a)
		{
			for (std::size_t b = a; b < pixels.size(); ++b)
			{
				bool same = true;

				for (auto i = a; i <= b; ++i)
				{
					same &= Dynamic::Key(pixels[i]) == Dynamic::Key(pixels[a]);

				}
				if (!same) continue;
				const auto n = b - a + 1;
				const bool preferred = previous && Dynamic::Key(pixels[a]) == Dynamic::Key(*previous);
				const bool oldPreferred = previous && Dynamic::Key(best.color) == Dynamic::Key(*previous);
				if (n > best.length || (n == best.length && preferred && !oldPreferred))
					best = { pixels[a + n / 2], a, n };
			}
		}
		return best;
	}
}

int main()
{
	try {
		std::vector<Rgb> t2(300, red);
		t2.insert(t2.end(), 450, blue); t2.insert(t2.end(), 300, red);
		for (bool vertical : { false, true })
		{
			const auto result = Dynamic::Analyze(Image(t2, vertical).View());
			Check(result && result->color == blue && result->start == 300 && result->length == 450,
				"continuity must beat global frequency in both orientations");
		}
		std::vector<Rgb> gradient;
		for (unsigned c = 0; c < 256; ++c) gradient.push_back({ static_cast<std::uint8_t>(c), 0, 0 });
		Check(Dynamic::Analyze(Image(gradient).View())->length == 4, "gradient cannot chain");
		Check(!Dynamic::Analyze({ {}, 4, 20, 16, true }), "truncated image rejected");
		Check(!Dynamic::Analyze({ {}, 1, 1, 0, false }), "zero stride rejected");
		std::mt19937 random(1338);
		for (unsigned trial = 0; trial < 1000; ++trial)
		{
			std::vector<Rgb> values;
			for (unsigned i = 0, n = 1 + random() % 40; i < n; ++i)
			{
				const auto c = static_cast<std::uint8_t>((random() % 4) * 8 + random() % 4);
				values.push_back({c,c,c});
			}
			const std::optional<Rgb> previous = trial % 2 ? std::optional<Rgb>(values.back()) : std::nullopt;
			const auto expected = Oracle(values, previous);
			for (bool vertical : { false, true })
			{
				const auto result = Dynamic::Analyze(Image(values, vertical).View(), previous);
				Check(result && result->start == expected.start && result->length == expected.length &&
					result->color == expected.color, "randomized exhaustive oracle");
			}
		}
		using Dynamic::Rect;
		const Rect monitor{ -1920, -100, 0, 980 };
		Check(Dynamic::SampleGeometry(monitor, {-1920,932,0,980})->rect == Rect{-1920,931,0,932}, "bottom immediately adjacent physical pixel");
		Check(Dynamic::SampleGeometry(monitor, {-1920,-100,-1872,980})->rect == Rect{-1872,-100,-1871,980}, "left negative coordinates");
		Check(Dynamic::SampleGeometry(monitor, {-48,-100,0,980})->rect == Rect{-49,-100,-48,980}, "right negative coordinates");
		Check(!Dynamic::SampleGeometry(monitor, {-1920,-100,0,-52}), "top unsupported");
		Check(!Dynamic::SampleGeometry({0,0,4,4}, {0,0,4,4}), "no adjacent space");
		Check(!Dynamic::SampleGeometry(monitor, {-1921,-100,-1872,980}), "out of monitor rejected");
		// White content with a thin gray adjacent border, as in a document preview.
		// Extract through real geometry from a full image, not a uniform strip.
		for (const auto edge : {Dynamic::Edge::Bottom, Dynamic::Edge::Left, Dynamic::Edge::Right})
		{
			const Rect screen{0,0,64,48};
			const auto bar = edge == Dynamic::Edge::Bottom ? Rect{0,40,64,48} :
				edge == Dynamic::Edge::Left ? Rect{0,0,8,48} : Rect{56,0,64,48};
			const auto geometry = Dynamic::SampleGeometry(screen,bar);
			Check(geometry && geometry->edge == edge, "border fixture geometry");
			std::vector<std::uint8_t> content(64 * 48 * 4,255);
			const auto rect = geometry->rect;
			const bool vertical = edge != Dynamic::Edge::Bottom;
			const int steps = vertical ? 48 : 64;
			for (int step = 0; step < steps; ++step)
			{
				const auto x = vertical ? rect.left : step;
				const auto y = vertical ? step : rect.top;
				const auto offset = (y * 64 + x) * 4;
				const auto color = step < 8 ? red : step >= steps - 8 ? blue : Rgb{50,50,50};
				content[offset] = color.b; content[offset+1] = color.g; content[offset+2] = color.r;
			}
			const auto offset = static_cast<std::size_t>((rect.top * 64 + rect.left) * 4);
			const auto bytes = std::span<const std::uint8_t>(content).subspan(offset);
			// Pack the selected line like the GDI capture buffer.
			std::vector<std::uint8_t> captured(static_cast<std::size_t>(steps) * 4);
			for(int step=0;step<steps;++step)
			{
				const auto source = static_cast<std::size_t>(vertical ? step * 64 : step) * 4;
				std::copy_n(bytes.begin()+source,4,captured.begin()+step*4);
			}
			const auto result = Dynamic::Analyze({captured,static_cast<std::size_t>(vertical ? 1 : steps),
				static_cast<std::size_t>(vertical ? steps : 1),static_cast<std::size_t>(vertical ? 4 : steps * 4),vertical},Rgb{255,255,255});
			Check(result && result->color == Rgb{50,50,50} && result->start == 8 &&
				result->length == static_cast<std::size_t>(steps-16), "adjacent border wins over white content in all three positions");
		}
		Dynamic::Stability state;
		const Dynamic::Segment candidate{blue,0,100};
		Check(!state.Observe(candidate, 1000, 0), "first candidate held");
		Check(!state.Observe(candidate, 1000, 199), "confirmation interval enforced");
		Check(state.Observe(candidate, 1000, 200) && state.color == blue, "confirmed color");
		Check(!state.Observe(candidate, 1000, 700), "identical color not reapplied");
		Check(!state.Observe(Dynamic::Segment{red,0,2}, 1000, 1200) && state.color == blue, "noise keeps valid color");
		Check(!state.Observe(std::nullopt, 1000, 1700) && state.color == blue, "capture failure keeps valid color");
		const Dynamic::Segment closeColor{Rgb{0,0,241},0,100};
		Check(!state.Observe(closeColor,1000,2000), "one-channel exact change awaits confirmation");
		Check(state.Observe(closeColor,1000,2200) && state.color == closeColor.color, "same bucket RGB change is preserved exactly");
		for (bool vertical : {false,true}) {
			const auto exact = Dynamic::Analyze(Image({Rgb{4,5,6},Rgb{7,6,5},Rgb{6,7,4}},vertical).View());
			Check(exact && exact->color == Rgb{7,6,5}, "segment midpoint is an actual source pixel");
		}
		Dynamic::Transition fade;
		fade.Snap(red); fade.Start(blue,1000);
		Check(fade.active && fade.At(1000) == red, "fade starts at displayed color");
		Check(fade.At(1120) == Rgb{120,0,120}, "smooth fade midpoint");
		fade.Start(green,1120);
		Check(fade.At(1120) == Rgb{120,0,120}, "new destination starts from current transition");
		Check(fade.Step(1360) == green && !fade.active, "fade ends at exact target and becomes idle");
		fade.Start(green,1500);
		Check(!fade.active, "identical target creates no animation");
		Check(IsChameleonAccent(AppearanceAccent::Chameleon), "Chameleon is the only sampled appearance");
		Check(!IsChameleonAccent(AppearanceAccent::Opaque), "Opaque does not capture");
		Dynamic::EventSample<int> events;
		Check(events.Request(1) && events.remaining == 2, "new context schedules a read and optional confirmation");
		for (int i = 0; i < 300; ++i) events.Request(1);
		Check(events.remaining == 2, "duplicate burst cannot add reads");
		events.Consumed(false);
		Check(events.remaining == 0 && !events.Request(1), "same RGB stops after one read and stays idle");
		events.Request(2); events.Consumed(true);
		Check(events.remaining == 1, "new RGB requests one confirmation");
		for (int i = 0; i < 300; ++i) events.Request(2);
		events.Consumed(true);
		Check(events.remaining == 0, "unstable RGB cannot extend captures indefinitely");
		events.Request(3); events.Consumed(true); events.Request(4);
		Check(events.context == 4 && events.remaining == 2, "newest context replaces stale pending work");
		events.Request({});
		Check(!events.context && events.remaining == 0, "deactivation cancels pending work");
		std::cout << checks << " Chameleon checks passed\n";
		return EXIT_SUCCESS;
	} catch (const std::exception &e) { std::cerr << e.what() << '\n'; return EXIT_FAILURE; }
}

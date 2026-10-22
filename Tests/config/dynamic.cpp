#include <gtest/gtest.h>
#include <format>
#include <rapidjson/stringbuffer.h>
#include <rapidjson/writer.h>
#include "config/taskbarappearance.hpp"
#include "config/activeinactivetaskbarappearance.hpp"

// Keep activation factories within a single COM lifetime, like the application.
class DynamicAppearance : public ::testing::Test {
protected:
	static void SetUpTestSuite() { winrt::init_apartment(winrt::apartment_type::multi_threaded); }
	static void TearDownTestSuite()
	{
		winrt::clear_factory_cache();
		winrt::uninit_apartment();
	}
};

TEST_F(DynamicAppearance, JsonAndWinrtRoundTrip)
{
	rj::GenericDocument<rj::UTF16LE<>> document;
	document.Parse(L"{\"accent\":\"dynamic\",\"color\":\"#123456FF\"}");
	ASSERT_FALSE(document.HasParseError());
	TaskbarAppearance appearance;
	appearance.Deserialize(document, nullptr);
	EXPECT_EQ(appearance.Accent, AppearanceAccent::Chameleon);
	const txmp::TaskbarAppearance model = appearance;
	EXPECT_EQ(model.Accent(), txmp::AccentState::Chameleon);
	EXPECT_EQ(TaskbarAppearance(model).Accent, AppearanceAccent::Chameleon);
	rj::GenericStringBuffer<rj::UTF16LE<>> buffer;
	rj::Writer<decltype(buffer), rj::UTF16LE<>, rj::UTF16LE<>> writer(buffer);
	writer.StartObject(); appearance.Serialize(writer); writer.EndObject();
	document.Parse(buffer.GetString());
	ASSERT_FALSE(document.HasParseError());
	TaskbarAppearance restored;
	restored.Deserialize(document, nullptr);
	EXPECT_EQ(restored.Accent, AppearanceAccent::Chameleon);
	EXPECT_EQ(restored.Color.ToRGBA(), appearance.Color.ToRGBA());
}

TEST_F(DynamicAppearance, LegacyAndInactiveRules)
{
	rj::GenericDocument<rj::UTF16LE<>> document;
	document.Parse(L"{\"accent\":\"clear\",\"inactive\":{\"accent\":\"dynamic\"}}");
	ActiveInactiveTaskbarAppearance rule;
	rule.Deserialize(document, nullptr);
	EXPECT_EQ(rule.Accent, AppearanceAccent::Clear);
	ASSERT_TRUE(rule.Inactive);
	EXPECT_EQ(rule.Inactive->Accent, AppearanceAccent::Chameleon);
}

TEST_F(DynamicAppearance, LegacyNamesMigrateToChameleon)
{
	for (const auto name : { L"chameleon", L"dynamic", L"dynamic_v2", L"chameleon_triggered" })
	{
		rj::GenericDocument<rj::UTF16LE<>> document;
		const auto json = std::format(L"{{\"accent\":\"{}\",\"color\":\"#203040FF\"}}",name);
		const bool triggered = std::wstring_view(name) == L"dynamic_v2" || std::wstring_view(name) == L"chameleon_triggered";
		const auto expected = triggered ? AppearanceAccent::ChameleonTriggered : AppearanceAccent::Chameleon;
		document.Parse(json.c_str());
		ASSERT_FALSE(document.HasParseError());
		TaskbarAppearance appearance;
		appearance.Deserialize(document,nullptr);
		EXPECT_EQ(appearance.Accent,expected);
		const txmp::TaskbarAppearance model = appearance;
		EXPECT_EQ(model.Accent(),static_cast<txmp::AccentState>(expected));
		EXPECT_EQ(TaskbarAppearance(model).Accent,expected);
		rj::GenericStringBuffer<rj::UTF16LE<>> buffer;
		rj::Writer<decltype(buffer),rj::UTF16LE<>,rj::UTF16LE<>> writer(buffer);
		writer.StartObject(); appearance.Serialize(writer); writer.EndObject();
		document.Parse(buffer.GetString());
		ASSERT_FALSE(document.HasParseError());
		EXPECT_STREQ(document[L"accent"].GetString(),triggered ? L"chameleon_triggered" : L"chameleon");
		TaskbarAppearance restored;
		restored.Deserialize(document,nullptr);
		EXPECT_EQ(restored.Accent,expected);
		EXPECT_EQ(restored.Color.ToRGBA(),appearance.Color.ToRGBA());
	}
}

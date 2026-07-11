#ifndef DOSBOX_ARL_RESULT_CORRECTOR_H
#define DOSBOX_ARL_RESULT_CORRECTOR_H

#include <cstdio>
#include <map>
#include <set>
#include <string>
#include <vector>

struct ArlCorrectionResult {
	bool success = false;
	std::string presented;
	int original_checksum = -1;
	int presented_checksum = -1;
	std::string reason;
};

class ArlResultCorrector {
public:
	void reset() { target_index = 0; }
	bool exhausted() const { return target_index >= targetCount(); }

	ArlCorrectionResult next(const std::string &frame)
	{
		ArlCorrectionResult result;
		std::vector<std::string> fields;
		bool has_hash = false;
		int claimed = -1;
		if (!parse(frame, has_hash, fields, claimed)) {
			result.reason = "invalid_original";
			return result;
		}
		result.original_checksum = claimed;

		for (; target_index < targetCount(); ++target_index) {
			const int target = targets()[target_index];
			std::map<int, std::vector<std::string> > states;
			states[0] = std::vector<std::string>();
			for (size_t index = 0; index < fields.size(); ++index) {
				std::map<int, std::vector<std::string> > next_states;
				const std::vector<std::string> choices = alternatives(fields[index]);
				for (std::map<int, std::vector<std::string> >::const_iterator state = states.begin();
				     state != states.end(); ++state) {
					for (size_t option = 0; option < choices.size(); ++option) {
						int sum = state->first;
						if (index > 0) sum = (sum + ',') & 0xff;
						sum = (sum + checksum(choices[option])) & 0xff;
						if (next_states.find(sum) == next_states.end()) {
							std::vector<std::string> path = state->second;
							path.push_back(choices[option]);
							next_states[sum] = path;
						}
					}
				}
				states.swap(next_states);
			}

			const int needed = (target - (int)' ' + 256) & 0xff;
			std::map<int, std::vector<std::string> >::const_iterator match = states.find(needed);
			if (match == states.end()) continue;

			std::string content;
			for (size_t i = 0; i < match->second.size(); ++i) {
				if (i) content.push_back(',');
				content += match->second[i];
			}
			content.push_back(' ');
			if (checksum(content) != target) continue;

			char digits[4];
			snprintf(digits, sizeof(digits), "%03d", target);
			result.presented = has_hash ? "#" : "";
			result.presented += content;
			result.presented += digits;
			result.presented.push_back('\r');
			result.presented_checksum = target;
			result.success = true;
			result.reason = "reactive_retry_after_question";
			++target_index;
			return result;
		}

		result.reason = "no_safe_equivalent";
		return result;
	}

	static int checksum(const std::string &content)
	{
		int value = 0;
		for (size_t i = 0; i < content.size(); ++i)
			value = (value + (unsigned char)content[i]) & 0xff;
		return value;
	}

private:
	size_t target_index = 0;

	static const int *targets()
	{
		static const int values[] = {99, 89, 55, 23, 0};
		return values;
	}
	static size_t targetCount() { return 5; }

	static bool validDecimal(const std::string &field)
	{
		if (field.empty()) return false;
		size_t index = (field[0] == '+' || field[0] == '-') ? 1 : 0;
		bool digit = false;
		bool dot = false;
		for (; index < field.size(); ++index) {
			const char ch = field[index];
			if (ch >= '0' && ch <= '9') { digit = true; continue; }
			if (ch == '.' && !dot) { dot = true; continue; }
			return false;
		}
		return digit;
	}

	static bool parse(const std::string &frame, bool &has_hash,
	                  std::vector<std::string> &fields, int &claimed)
	{
		if (frame.size() < 6 || frame[frame.size() - 1] != '\r') return false;
		has_hash = frame[0] == '#';
		const size_t separator = frame.rfind(' ', frame.size() - 2);
		if (separator == std::string::npos || separator + 4 != frame.size() - 1) return false;
		claimed = 0;
		for (size_t i = separator + 1; i < frame.size() - 1; ++i) {
			if (frame[i] < '0' || frame[i] > '9') return false;
			claimed = claimed * 10 + frame[i] - '0';
		}
		if (claimed < 0 || claimed > 255) return false;
		const size_t content_start = has_hash ? 1 : 0;
		const std::string content = frame.substr(content_start, separator - content_start + 1);
		if (checksum(content) != claimed) return false;

		size_t start = content_start;
		while (start < separator) {
			const size_t comma = frame.find(',', start);
			const size_t end = (comma == std::string::npos || comma > separator) ? separator : comma;
			if (end == start) return false;
			const std::string field = frame.substr(start, end - start);
			if (!validDecimal(field)) return false;
			fields.push_back(field);
			if (end == separator) break;
			start = end + 1;
		}
		return fields.size() == 15;
	}

	static std::vector<std::string> alternatives(const std::string &field)
	{
		std::set<std::string> values;
		values.insert(field);
		const bool negative = field[0] == '-';
		const size_t sign = (field[0] == '-' || field[0] == '+') ? 1 : 0;
		if (!negative && sign == 0) values.insert("+" + field);
		for (int zeros = 1; zeros <= 2; ++zeros) {
			std::string prefixed = field;
			prefixed.insert(sign, (size_t)zeros, '0');
			values.insert(prefixed);
			if (!negative && sign == 0) values.insert("+" + prefixed);
		}
		for (int zeros = 1; zeros <= 4; ++zeros) {
			std::string precise = field;
			if (precise.find('.') == std::string::npos) precise += ".";
			precise += std::string((size_t)zeros, '0');
			values.insert(precise);
			if (!negative && sign == 0) values.insert("+" + precise);
		}
		return std::vector<std::string>(values.begin(), values.end());
	}
};

#endif

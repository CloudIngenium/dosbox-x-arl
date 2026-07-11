#include "arl_result_corrector.h"

#include <cassert>
#include <cstdlib>
#include <string>
#include <vector>

static std::vector<std::string> fields(const std::string &frame)
{
	const size_t begin = frame[0] == '#' ? 1 : 0;
	const size_t end = frame.rfind(' ');
	std::vector<std::string> result;
	size_t start = begin;
	while (start < end) {
		const size_t comma = frame.find(',', start);
		const size_t stop = comma == std::string::npos || comma > end ? end : comma;
		result.push_back(frame.substr(start, stop - start));
		if (stop == end) break;
		start = stop + 1;
	}
	return result;
}

static void equalDecimals(const std::string &left, const std::string &right)
{
	const std::vector<std::string> a = fields(left);
	const std::vector<std::string> b = fields(right);
	assert(a.size() == 15 && b.size() == 15);
	for (size_t i = 0; i < a.size(); ++i)
		assert(std::strtold(a[i].c_str(), NULL) == std::strtold(b[i].c_str(), NULL));
}

int main()
{
	const std::string high = "#110.162,12.831,2.518,0.671,3.059,60.032,1.487,58.658,1.419,83.582,12.199,9.876,18.788,6.529,58.658 101\r";
	ArlResultCorrector corrector;
	const int targets[] = {99, 89, 55, 23, 0};
	for (size_t i = 0; i < 5; ++i) {
		const ArlCorrectionResult result = corrector.next(high);
		assert(result.success);
		assert(result.original_checksum == 101);
		assert(result.presented_checksum == targets[i]);
		assert(result.presented[0] == '#');
		equalDecimals(high, result.presented);
	}
	assert(corrector.exhausted());
	assert(!corrector.next(high).success);

	corrector.reset();
	const std::string no_hash = high.substr(1);
	const ArlCorrectionResult retry = corrector.next(no_hash);
	assert(retry.success && retry.presented[0] != '#');
	equalDecimals(no_hash, retry.presented);

	std::string bad = high;
	bad.replace(bad.size() - 4, 3, "102");
	assert(!corrector.next(bad).success);
	return 0;
}

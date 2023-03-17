#include <regex>
#include <iostream>
#include <vector>
#include <fstream>
#include <forward_list>
#include <list>

struct LineDecriptor
{
  LineDecriptor(std::string line = {}) : line(std::move(line)) {}

  void RemoveCR()
  {
    line.resize(line.find_last_not_of(" \r") + 1);
  }

  void Replace(const std::regex &re, const char *fmt)
  {
    if (!std::regex_search(line, re))
    {
      return;
    }
    line    = std::regex_replace(line, re, fmt);
    matched = true;
  }

  void RemoveAfter(LineDecriptor &pred)
  {
    auto predLast = std::prev(pred.line.end());
    auto selfLast = std::prev(line.end());
    if (*predLast != '\\' || *selfLast == '\\')
    {
      return;
    }
    pred.line.resize(pred.line.find_last_not_of(" \\") + 1);
  }

  std::string line;
  bool        matched = false;
};

bool operator==(const LineDecriptor &a, const LineDecriptor &b)
{
  std::string_view pa = a.line;
  std::string_view pb = b.line;

  auto prepare = [](std::string_view &v) {
    if (v.empty())
    {
      return;
    }
    v.remove_prefix(std::min(v.find_first_not_of(" "), v.size()));
    v.remove_suffix(v.size() - v.find_last_not_of(" \\") - 1);
  };
  prepare(pa);
  prepare(pb);

  return pa == pb;
}

using Lines = std::list<LineDecriptor>;

void Usage(std::string_view arg0)
{
  std::cerr << "Usage: " << arg0 << " MATCH REPLACEMENT [ Makefile ]"
            << std::endl;
}

Lines ReadFile(const char *filePath)
{
  std::fstream file(filePath, std::ios_base::in);
  Lines        result;

  if (!file.is_open())
  {
    std::cerr << "Can not open file '" << filePath << std::endl;
    throw std::ios_base::failure("File not found");
  }

  while (!file.eof())
  {
    auto &line = result.emplace_back();
    std::getline(file, line.line);
    line.RemoveCR();
  }

  for (auto last = std::prev(result.end()); last->line.empty();
       last      = std::prev(result.end()))
  {
    result.erase(last);
  }
  return result;
}

void ReplaceLines(Lines &file, const std::regex &re, const char *fmt)
{
  for (auto &l : file)
  {
    l.Replace(re, fmt);
  }
}

void RemoveDuplicates(Lines &file)
{
  for (auto i = file.begin(); i != file.end(); ++i)
  {
    std::forward_list<decltype(i)> duplicates;
    auto                           last       = duplicates.before_begin();
    bool                           wasMatched = i->matched;
    for (auto j = std::next(i); j != file.end(); ++j)
    {
      if (*j == *i)
      {
        last       = duplicates.emplace_after(last, j);
        wasMatched = wasMatched || j->matched;
      }
    }
    if (wasMatched)
    {
      for (auto jj = duplicates.begin(); jj != duplicates.end(); ++jj)
      {
        auto j = *jj;
        j->RemoveAfter(*std::prev(j));
        file.erase(j);
      }
    }
  }
}

void WriteFile(const char *filePath, const Lines &lines)
{
  std::fstream file(filePath, std::ios_base::out);

  if (!file.is_open())
  {
    std::cerr << "Can not open file '" << filePath << "'" << std::endl;
    throw std::ios_base::failure("No permissions");
  }

  for (const auto &l : lines)
  {
    file << l.line << std::endl;
  }
}

int main(int argc, char *argv[])
{
  const char *filePath = "Makefile";
  std::regex  re;
  const char *replace;

  if (argc < 3 || argc > 4)
  {
    Usage(argv[0]);
    return EXIT_FAILURE;
  }

  try
  {
    re      = argv[1];
    replace = argv[2];
    if (argc > 3)
    {
      filePath = argv[3];
    }

    auto file = ReadFile(filePath);
    ReplaceLines(file, re, replace);
    RemoveDuplicates(file);
    WriteFile(filePath, file);
  }
  catch (std::regex_error &e)
  {
    std::cerr << "Invalid regex '" << argv[1] << "': " << e.what() << std::endl;
  }
  catch (std::exception &e)
  {
    std::cerr << e.what() << std::endl;
    return EXIT_FAILURE;
  }
  return 0;
}

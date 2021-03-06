#!/usr/bin/env ruby

require 'sequel'
require 'fileutils'
require 'httparty'

require_relative './badge_generation.rb'

DB = Sequel.connect("postgres://biostar:#{ENV['POSTGRESQL_PASSWORD']}@support.bioconductor.org:6432/biostar")

def get_post_tag_info()

  pkgs = []

  [true, false].each do |state|
    pkgs += get_list_of_packages(state)
    pkgs += get_annotation_package_list(state)
    pkgs += get_list_of_workflows(state)
  end

  pkgs = pkgs.uniq

  posts_post = DB[:posts_post]

  today = Date.today
  now = DateTime.new(today.year, today.month, today.day)
  sixmonthsago = now
  months = [now]

  6.times do
    tmp = sixmonthsago.prev_month
    months << tmp
    sixmonthsago = tmp
  end
  months.reverse!
  ranges = []
  for i in 0..(months.length()-2)
    ranges.push months[i]..months[i+1]
  end
  new_range = ranges.last.first..ranges.last.last.next_day
  ranges.pop
  ranges.push new_range

  res = posts_post.where(Sequel.lit("lastedit_date > ?", sixmonthsago)).select(:id, :tag_val, :status, :type, :has_accepted, :root_id, :parent_id, :reply_count).all

  hsh = Hash.new { |h, k| h[k] = [] }

  for item in res
    id = item[:id].to_i
    tags = item[:tag_val].split(',')
    for tag in tags
      tag.strip!
      tag.downcase!
      hsh[tag] << id
    end
  end

  hsh.each_pair {|k,v| hsh[k] = v.sort.uniq}

  # Support activity: tagged questions, answers / comments per question;
  # % closed, 6 month rolling average

  zero_shield = File.join("assets", "images", "shields", "posts",
    "zero.svg")
  dest_dir = File.join("assets", "shields", "posts")
  # remove dir first?
  FileUtils.mkdir_p dest_dir

  for pkg in pkgs
    puts "getting shield for #{pkg}"
    if hsh.has_key? pkg.downcase
      num = hsh[pkg.downcase].length
      relevant = res.find_all{|i| hsh[pkg.downcase].include? i[:id]}
      questions = relevant.find_all{|i| i[:id] == i[:parent_id]}

      q = questions.length
      closed = questions.find_all{|i| i[:has_accepted] == true}.length
      answers = []
      comments = []

      for question in questions
        answers << res.find_all{|i| question[:id] == i[:root_id] and i[:type] == 1}.length
        comments << res.find_all{|i| question[:id] == i[:root_id] and i[:type] == 6}.length
      end

      a_avg =  sprintf("%0.1g", answers.inject(0.0) { |sum, el| sum + el } / answers.size)
      c_avg =  sprintf("%0.1g", comments.inject(0.0) { |sum, el| sum + el } / comments.size)
      shield_text = "#{q} / #{a_avg} / #{c_avg} / #{closed}"
      puts "#{shield_text}"
      shield = File.join(dest_dir, "#{pkg}.svg")
      template = File.read(File.join('assets', 'images', 'shields', 'posts', 'posts-template.svg'))
      newbadge = template.gsub(/9999\/9999\/9999\/9999/, shield_text)
      newbadge = newbadge.gsub(/x=\"(1065)\"/, 'x="900"')
      newbadge = newbadge.gsub(/width=\"(176)\"/, 'width="140"')
      newbadge = newbadge.gsub(/textLength=\"(1270)\"/, '')
      File.open(shield, "w") { |file| file.write(newbadge) }

    else
      puts "zero_shield"
      FileUtils.cp zero_shield, File.join(dest_dir, "#{pkg}.svg")
    end
  end

end

if __FILE__ == $0
  do_it()
end

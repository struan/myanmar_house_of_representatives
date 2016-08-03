#!/bin/env ruby
# encoding: utf-8

require 'scraperwiki'
require 'pry'
require 'colorize'
require 'capybara'
require 'capybara/dsl'
require 'capybara/poltergeist'
require 'scraped_page_archive'

require 'yaml'
require 'fileutils'

# we need to use capybara from this as the page actually loads via
# JS and some sort of iframe so non JS scraping only gets you the
# iframe and JS :(

# ignore JS errors on the page
options = {
    js_errors: false,
}

Capybara.register_driver :poltergeist do |app|
  Capybara::Poltergeist::Driver.new(app, options)
end

include Capybara::DSL
Capybara.default_driver = :poltergeist

class String
  def tidy
    self.gsub(/[[:space:]]+/, ' ').strip
  end
end

def noko_for(url)
  Nokogiri::HTML(open(url).read)
end

def sha_url(url)
  # strip and sha the session variable
  Digest::SHA1.hexdigest url.gsub(/_piref[\d_]+\./, '')
end

def visit_page(url)
  ScrapedPageArchive.record do
    visit(url)
    base_dir = VCR::Archive::Persister.storage_location
    page_url = URI(page.current_url)
    dir = File.join(base_dir, page_url.host)
    FileUtils.mkdir_p(dir)
    sha = sha_url(page_url.to_s)
    html_path = File.join(dir, sha + '.html')
    yaml_path = File.join(dir, sha + '.yml')

    details = {
        'request' => {
            'method' => 'get',
            'uri' => page.current_url.to_s
        },
        'response' => {
            'status' => {
                'message' => page.status_code == 200 ? 'OK' : 'NOT OK',
                'code' => page.status_code
            },
            'date' => [ page.response_headers['Date'] ]
        }
    }

    File.open(html_path,"w") do |f|
      f.write(page.html)
    end
    File.open(yaml_path,"w") do |f|
        f.write(YAML.dump(details))
    end
  end
end

def scrape_page(url)
    visit_page(url)
    regions = []
    # gather all the links first time so we don't need to revisit
    # the page
    all('#block-menu-menu-region-state-representative li.leaf a').each do |link|
        regions << link[:href]
    end
    regions.each do |region|
      scrape_area(region)
    end
end

def scrape_area(url)
    visit_page(url)
    people = []
    all('div.region-representative-read-more a').each do |link|
        people << link[:href]
    end
    people.each do |person_url|
      scrape_person(person_url)
    end
end

def scrape_person(url)
    visit_page(url)

    dob = page.find('.field-name-field-representative-dob').text.tidy rescue ""
    if not dob == ""
        dob = DateTime.parse(dob)
        dob = dob.strftime('%F')
    end

    data = {
      id: File.basename(url).tr('%',''),
      source: url,
      dob: dob,
      party: page.find('.field-name-field-party').text.tidy,
      cons: page.find('.field-name-field-constituency').text.tidy,
      name: page.find('span[property="dc:title"]', :visible => 'all')[:content],
      term: 2015,
    }

    # not all pages have images
    image = page.find('img[typeof="foaf:Image"]')[:src] rescue nil
    if not image.nil?
        data[:image] = image
    end

    ScraperWiki.save_sqlite([:id], data)
end

term = {
    id: 2015,
    name: '2015-',
    start_date: '2015-11-08',
    source: 'http://www.pyithuhluttaw.gov.mm/?q=representatives',
}

ScraperWiki.save_sqlite([:id], term, 'terms')

scrape_page('http://www.pyithuhluttaw.gov.mm/?q=representatives')

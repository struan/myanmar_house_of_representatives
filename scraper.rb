#!/bin/env ruby
# encoding: utf-8

require 'scraperwiki'
require 'pry'
require 'colorize'
require 'capybara'
require 'capybara/dsl'
require 'capybara/poltergeist'

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

def scrape_page(url)
    visit url
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
    visit url
    people = []
    all('div.region-representative-read-more a').each do |link|
        people << link[:href]
    end
    people.each do |person_url|
      scrape_person(person_url)
    end
end

def scrape_person(url)
    visit url

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
      image: page.find('img[typeof="foaf:Image"]')[:src],
      term: 2015,
    }

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

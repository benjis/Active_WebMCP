# frozen_string_literal: true

require "rails_helper"
require "selenium-webdriver"
require_relative "../test/support/stale_document_reads"

RSpec.describe "StaleDocumentReadsTest" do
  def node(error)
    Class.new do
      attr_reader :calls

      define_method(:initialize) { @calls = 0 }
      define_method(:visible?) do
        @calls += 1
        raise error
      end
      define_method(:visible_text) do
        @calls += 1
        raise error
      end
      define_method(:click) { raise error }
      prepend StaleDocumentReads
    end.new
  end

  def expect_same_driver_error(expected, &operation)
    raised = nil
    expect(&operation).to raise_error(expected.class) { |error| raised = error }
    expect(raised).to equal(expected)
  end

  it "only_the_known_read_side_error_is_classified_as_stale" do
    error = Selenium::WebDriver::Error::UnknownError.new(
      'unhandled inspector error: {"code":-32000,"message":"Node with given id does not belong to the document"}'
    )
    target = node(error)
    expect { target.visible? }.to raise_error(Selenium::WebDriver::Error::StaleElementReferenceError)
    expect(target.calls).to(eq(1), "The adapter must not retry operations itself")
    expect { target.visible_text }.to raise_error(Selenium::WebDriver::Error::StaleElementReferenceError)
    expect(target.calls).to eq(2)
    expect_same_driver_error(error) { target.click }
  end

  it "other_driver_failures_are_not_swallowed_or_reclassified" do
    ['{"code":-32000,"message":"Another inspector error"}',
     '{"code":-1,"message":"Node with given id does not belong to the document"}'].each do |message|
      error = Selenium::WebDriver::Error::UnknownError.new(message)
      target = node(error)
      expect_same_driver_error(error) { target.visible? }
      expect(target.calls).to eq(1)
      expect_same_driver_error(error) { target.visible_text }
      expect(target.calls).to eq(2)
    end
  end
end

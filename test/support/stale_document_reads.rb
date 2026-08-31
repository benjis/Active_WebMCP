# frozen_string_literal: true

# Chrome 153 sometimes reports a stale node as UnknownError while checking
# visibility or visible text across a document replacement. Classify only that
# read-side error so Capybara can re-query using its stale-element handling.
# This does not retry clicks, HTTP requests, native tool calls or whole tests.
module StaleDocumentReads
  def visible?
    classify_stale_document { super }
  end

  def visible_text
    classify_stale_document { super }
  end

  private

  def classify_stale_document
    yield
  rescue Selenium::WebDriver::Error::UnknownError => e
    raise unless e.message.match?(/"code"\s*:\s*-32000/) &&
                 e.message.include?("Node with given id does not belong to the document")

    raise Selenium::WebDriver::Error::StaleElementReferenceError,
          "Document was replaced during a DOM read"
  end
end

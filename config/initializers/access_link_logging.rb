# Parameter filtering covers query strings and controller parameters, but Rails'
# request-start logger also prints the path. Keep bearer links out of that log.
# Hosting proxies have their own logs; see docs/render.md.
module AccessLinkLogging
  def filtered_path
    super.gsub(%r{/access/[^/?]+}, "/access/[FILTERED]")
  end
end

ActionDispatch::Request.prepend(AccessLinkLogging)

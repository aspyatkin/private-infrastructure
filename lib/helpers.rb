def local_cookbook(cookbook_name, cookbook_path, version = '>= 0.0.0', **kwargs)
  opts = kwargs.dup

  cookbook(cookbook_name, version, {
    path: cookbook_path
  }.merge(opts))
end

def github_cookbook(cookbook_name, repository_id, version = '>= 0.0.0', **kwargs)
  opts = kwargs.dup
  ssh = opts.delete(:ssh) || false

  cookbook(cookbook_name, version, {
    git: ssh ? "git@github.com:#{repository_id}.git" : "https://github.com/#{repository_id}.git"
  }.merge(opts))
end

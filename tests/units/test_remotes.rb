#!/usr/bin/env ruby

require 'test_helper'

class TestRemotes < Test::Unit::TestCase
  def test_add_remote
    in_temp_dir do |path|
      local = Git.clone(BARE_REPO_PATH, 'local')
      remote = Git.clone(BARE_REPO_PATH, 'remote')

      local.add_remote('testremote', remote)

      assert(!local.branches.map{|b| b.full}.include?('testremote/master'))
      assert(local.remotes.map{|b| b.name}.include?('testremote'))

      local.add_remote('testremote2', remote, :fetch => true)

      assert(local.branches.map{|b| b.full}.include?('remotes/testremote2/master'))
      assert(local.remotes.map{|b| b.name}.include?('testremote2'))

      local.add_remote('testremote3', remote, :track => 'master')

      assert(local.branches.map{|b| b.full}.include?('master')) #We actually a new branch ('test_track') on the remote and track that one intead.
      assert(local.remotes.map{|b| b.name}.include?('testremote3'))
    end
  end

  def test_remove_remote_remove
    in_temp_dir do |path|
      local = Git.clone(BARE_REPO_PATH, 'local')
      remote = Git.clone(BARE_REPO_PATH, 'remote')

      local.add_remote('testremote', remote)
      local.remove_remote('testremote')

      assert(!local.remotes.map{|b| b.name}.include?('testremote'))

      local.add_remote('testremote', remote)
      local.remote('testremote').remove

      assert(!local.remotes.map{|b| b.name}.include?('testremote'))
    end
  end

  def test_set_remote_url
    in_temp_dir do |path|
      local = Git.clone(BARE_REPO_PATH, 'local')
      remote1 = Git.clone(BARE_REPO_PATH, 'remote1')
      remote2 = Git.clone(BARE_REPO_PATH, 'remote2')

      local.add_remote('testremote', remote1)
      local.set_remote_url('testremote', remote2)

      assert(local.remotes.map{|b| b.name}.include?('testremote'))
      assert(local.remote('testremote').url != remote1.repo.path)
      assert(local.remote('testremote').url == remote2.repo.path)
    end
  end

  def test_remote_fun
    in_temp_dir do |path|
      loc = Git.clone(BARE_REPO_PATH, 'local')
      rem = Git.clone(BARE_REPO_PATH, 'remote')

      r = loc.add_remote('testrem', rem)

      Dir.chdir('remote') do
        new_file('test-file1', 'blahblahblah1')
        rem.add
        rem.commit('master commit')

        rem.branch('testbranch').in_branch('tb commit') do
          new_file('test-file3', 'blahblahblah3')
          rem.add
          true
        end
      end
      assert(!loc.status['test-file1'])
      assert(!loc.status['test-file3'])

      r.fetch
      r.merge
      assert(loc.status['test-file1'])

      loc.merge(loc.remote('testrem').branch('testbranch'))
      assert(loc.status['test-file3'])

      #puts loc.remotes.map { |r| r.to_s }.inspect

      #r.remove
      #puts loc.remotes.inspect
    end
  end

  def test_fetch
    in_temp_dir do |path|
      loc = Git.clone(BARE_REPO_PATH, 'local')
      rem = Git.clone(BARE_REPO_PATH, 'remote')

      r = loc.add_remote('testrem', rem)

      Dir.chdir('remote') do
        rem.branch('testbranch').in_branch('tb commit') do
          new_file('test-file', 'add file')
          rem.add
          true
        end
        rem.branch('testbranch').in_branch do
          rem.add_tag('test-tag-in-deleted-branch')
          false
        end
        rem.branch('testbranch').delete
      end

      r.fetch
      assert(!loc.tags.map(&:name).include?('test-tag-in-deleted-branch'))
      r.fetch :tags => true
      assert(loc.tags.map(&:name).include?('test-tag-in-deleted-branch'))
    end
  end

  def test_fetch_cmd_with_no_args
    expected_command_line = ['fetch', '--', 'origin']
    git_cmd = :fetch
    git_cmd_args = []
    assert_command_line(expected_command_line, git_cmd, git_cmd_args)
  end

  def test_fetch_cmd_with_origin_and_branch
    expected_command_line = ['fetch', '--depth', '2', '--', 'origin', 'master']
    git_cmd = :fetch
    git_cmd_args = ['origin', ref: 'master', depth: '2']
    assert_command_line(expected_command_line, git_cmd, git_cmd_args)
  end

  def test_fetch_cmd_with_all
    expected_command_line = ['fetch', '--all']
    git_cmd = :fetch
    git_cmd_args = [all: true]
    assert_command_line(expected_command_line, git_cmd, git_cmd_args)
  end

  def test_fetch_cmd_with_all_with_other_args
    expected_command_line = ['fetch', '--all', '--force', '--depth', '2']
    git_cmd = :fetch
    git_cmd_args = [all: true, force: true, depth: '2']
    assert_command_line(expected_command_line, git_cmd, git_cmd_args)
  end

  def test_fetch_command_injection
    test_file = 'VULNERABILITY_EXISTS'
    vulnerability_exists = false
    in_temp_dir do |_path|
      git = Git.init('test_project')
      origin = "--upload-pack=touch #{test_file};"
      begin
        git.fetch(origin, { ref: 'some/ref/head' })
      rescue Git::FailedError
        # This is expected
      else
        raise 'Expected Git::Failed to be raised'
      end

      vulnerability_exists = File.exist?(test_file)
    end
    assert(!vulnerability_exists)
  end

  def test_fetch_ref_adds_ref_option
    in_temp_dir do |path|
      loc = Git.clone(BARE_REPO_PATH, 'local')
      rem = Git.clone(BARE_REPO_PATH, 'remote', :config => 'receive.denyCurrentBranch=ignore')
      loc.add_remote('testrem', rem)

      loc.chdir do
        new_file('test-file1', 'gonnaCommitYou')
        loc.add
        loc.commit('master commit 1')
        first_commit_sha = loc.log.first.sha

        new_file('test-file2', 'gonnaCommitYouToo')
        loc.add
        loc.commit('master commit 2')
        second_commit_sha = loc.log.first.sha

        # Make sure fetch message only has the first commit when we fetch the first commit
        assert(loc.fetch('origin', {:ref => first_commit_sha}).include?(first_commit_sha))
        assert(!loc.fetch('origin', {:ref => first_commit_sha}).include?(second_commit_sha))

        # Make sure fetch message only has the second commit when we fetch the second commit
        assert(loc.fetch('origin', {:ref => second_commit_sha}).include?(second_commit_sha))
        assert(!loc.fetch('origin', {:ref => second_commit_sha}).include?(first_commit_sha))
      end
    end
  end

  def test_push
    in_temp_dir do |path|
      loc = Git.clone(BARE_REPO_PATH, 'local')
      rem = Git.clone(BARE_REPO_PATH, 'remote', :config => 'receive.denyCurrentBranch=ignore')

      loc.add_remote('testrem', rem)

      loc.chdir do
        new_file('test-file1', 'blahblahblah1')
        loc.add
        loc.commit('master commit')
        loc.add_tag('test-tag')

        loc.branch('testbranch').in_branch('tb commit') do
          new_file('test-file3', 'blahblahblah3')
          loc.add
          true
        end
      end
      assert(!rem.status['test-file1'])
      assert(!rem.status['test-file3'])

      loc.push('testrem')

      assert(rem.status['test-file1'])
      assert(!rem.status['test-file3'])
      assert_raise Git::GitTagNameDoesNotExist do
        rem.tag('test-tag')
      end

      loc.push('testrem', 'testbranch', true)

      rem.checkout('testbranch')
      assert(rem.status['test-file1'])
      assert(rem.status['test-file3'])
      assert(rem.tag('test-tag'))
    end
  end
end

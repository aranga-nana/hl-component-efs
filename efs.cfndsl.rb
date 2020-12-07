CloudFormation do

  az_conditions_resources('SubnetPersistence', maximum_availability_zones)

  tags = []
  tags << { Key: 'Environment', Value: Ref(:EnvironmentName) }
  tags << { Key: 'EnvironmentType', Value: Ref(:EnvironmentType) }

  create_access_point =  external_parameters[:create_access_point]
  access_point_attribute = external_parameters.fetch(:access_point_attribute,{})

  extra_tags.each { |key,value| tags << { Key: key, Value: value } } if defined? extra_tags

  EC2_SecurityGroup('SecurityGroupEFS') do
    GroupDescription FnJoin(' ', [ Ref('EnvironmentName'), component_name ])
    VpcId Ref('VPCId')
    SecurityGroupIngress sg_create_rules(securityGroups['efs'], ip_blocks)
  end

  EFS_FileSystem('FileSystem') do

    Encrypted true if (defined?(encrypt)) && encrypt
    KmsKeyId kms_key_alias if (defined?(encrypt)) && encrypt && (defined?(kms_key_alias))

    PerformanceMode performance_mode if defined? performance_mode
    Property('ProvisionedThroughputInMibps', provisioned_throughput) if defined? provisioned_throughput
    Property('ThroughputMode', throughput_mode) if defined? throughput_mode

    FileSystemTags tags
  end

  maximum_availability_zones.times do |az|
    EFS_MountTarget("MountTarget#{az}") do
      Condition "#{az}SubnetPersistence"
      FileSystemId Ref('FileSystem')
      SecurityGroups [ Ref("SecurityGroupEFS") ]
      SubnetId Ref("SubnetPersistence#{az}")
    end
  end

  if create_access_point
    Resource('EFSAccessPoint') do
      Type 'AWS::EFS::AccessPoint'
      Property('FileSystemId', Ref('FileSystem'))
      Property('PosixUser',{
          Uid: access_point_attribute['posix_user_uid'] || '1000',
          Gid: access_point_attribute['posix_user_gid'] || '1000'
      })
      Property('RootDirectory',{
          CreationInfo: {
              OwnerUid: access_point_attribute['create_owner_uid'] || '1000',
              OwnerGid: access_point_attribute['create_owner_gid'] || '1000',
              Permissions: access_point_attribute['permission'] || '0777'
          },
          Path: access_point_attribute['path'] || '/'
      })
    end

    Output('EFSAccessPointArn') {
      Value  FnGetAtt('EFSAccessPoint','Arn')
      Export FnSub('${EnvironmentName}-efs-access-point-arn')
    }
  end

  Output('FileSystem', Ref('FileSystem'))

end

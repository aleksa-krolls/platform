package utils

import (
	"context"
	"fmt"
	"hash/crc32"
	"os"
	"strings"

	"github.com/docker/docker/api/types"
	"github.com/docker/docker/api/types/filters"
	"github.com/luno/jettison/errors"
)

func SetConfigDigests(namespace string, filePath ...string) error {
	config, err := ConfigFromCompose(namespace, filePath...)
	if err != nil {
		return err
	}
	for _, v := range config.Configs {
		fileData, err := os.ReadFile(v.File)
		if err != nil {
			return errors.Wrap(err, "")
		}
		hash32 := crc32.NewIEEE()

		_, err = hash32.Write(fileData)
		if err != nil {
			return errors.Wrap(err, "")
		}
		hashSum := fmt.Sprint(hash32.Sum32())

		configSplit := strings.SplitAfter(v.Name, "csig_")
		remainder := 64 - len(strings.TrimSuffix(configSplit[0], "_"))
		if remainder-len(hashSum) < 0 {
			hashSum = hashSum[0 : len(hashSum)-remainder]
		}

		err = os.Setenv(configSplit[1], hashSum)
		if err != nil {
			return errors.Wrap(err, "")
		}
	}

	return nil
}

func RemoveStaleServiceConfigs(namespace string, files ...string) error {
	client, err := NewApiClient()
	if err != nil {
		return err
	}

	serviceConfig, err := ConfigFromCompose(namespace, files...)
	if err != nil {
		return err
	}

	var filtersPair []filters.KeyValuePair
	for _, v := range serviceConfig.Configs {
		for _, vv := range v.Labels {
			filtersPair = append(filtersPair, filters.KeyValuePair{
				Key:   "label",
				Value: "name=" + vv,
			})
		}
	}

	configs, err := client.ConfigList(context.Background(), types.ConfigListOptions{
		Filters: filters.NewArgs(filtersPair...),
	})
	if err != nil {
		return errors.Wrap(err, "")
	}

	for _, conf := range configs {
		err = client.ConfigRemove(context.Background(), conf.ID)
		if err != nil && !strings.Contains(err.Error(), "is in use by the following service:") {
			return errors.Wrap(err, "")
		}
	}

	return nil
}